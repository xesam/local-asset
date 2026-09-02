import {
  LocalAssetEngine,
  EngineResult,
  EngineFailure,
  engineSuccess,
  engineFailure,
} from '../api/LocalAssetEngine';
import { Policy } from '../api/Policy';
import { ResourceLoader } from '../api/ResourceLoader';
import { SchemeAdapter } from '../api/SchemeAdapter';
import { ResolverResult } from '../api/ResourceResolver';
import {
  EngineObserver,
  STAGE_ADAPTER_PARSE,
  STAGE_POLICY_PRE,
  STAGE_RESOLVE,
  STAGE_POLICY_POST,
  STAGE_LOAD,
  STAGE_COMPLETE,
} from '../api/EngineObserver';
import { AdapterRegistry } from '../internal/AdapterRegistry';
import { ResolverChain } from '../internal/ResolverChain';
import { AssetRequest } from '../model/AssetRequest';
import { ResolveContext, createResolveContext } from '../model/ResolveContext';
import { ResourceData } from '../model/ResourceData';
import { ResourceDescriptor } from '../model/ResourceDescriptor';
import { ResourceErrorCategory } from '../error/ResourceErrorCategory';
import { ResourceException } from '../error/ResourceException';

export interface DefaultLocalAssetEngineOptions {
  adapters: SchemeAdapter[];
  resolverChain: ResolverChain;
  policy: Policy;
  loader: ResourceLoader;
  observer?: EngineObserver | null;
}

/**
 * design.md §2.2 的流水线编排：parse → preCheck → resolverChain → postCheck → load。
 * 与 Kotlin `DefaultLocalAssetEngine` 逐行核对过；本类的全部实质内容就是
 * "哪一步失败 → 归到哪个 stage、哪个 category"，两条易错点：
 *
 * 1. **每一步各自 try/catch，且 catch 里的 stage 必须是该步自己的 stage。**
 *    把两步合进一个 try 会让前一步的异常被标成后一步的 stage —— 只断言 category 的
 *    测试看不出来（例如 preCheck 与 postCheck 的兜底 category 同为 SECURITY_ERROR）。
 * 2. **ResourceException 自带 category / stage 时一律保留**（见 toFailure）。
 *    尤其是 DefaultPolicy 对"资源过期"抛的是 RESOLUTION_ERROR @ policy_post ——
 *    检查写在 policy 里但语义属于解析结果，引擎不得因为"这是 policy 阶段"把它
 *    改写成 SECURITY_ERROR（design.md §3.5，Kotlin/iOS 同）。
 *
 * STAGE_RESOLVE 的观测事件由 ResolverChain 逐个 resolver 发出，引擎把自己的 observer
 * 透传下去，成功路径上不再补发；只有 resolve 阶段失败时引擎才自己发一条终止事件。
 */
export class DefaultLocalAssetEngine implements LocalAssetEngine {
  private readonly adapterRegistry: AdapterRegistry;
  private readonly resolverChain: ResolverChain;
  private readonly policy: Policy;
  private readonly loader: ResourceLoader;
  private readonly observer: EngineObserver | null;

  constructor(options: DefaultLocalAssetEngineOptions) {
    this.adapterRegistry = new AdapterRegistry(options.adapters);
    this.resolverChain = options.resolverChain;
    this.policy = options.policy;
    this.loader = options.loader;
    this.observer = options.observer ?? null;
  }

  resolveUrl(url: string, context: ResolveContext = createResolveContext()): EngineResult {
    let request: AssetRequest;
    try {
      request = this.adapterRegistry.select(url).parse(url);
    } catch (error) {
      return this.stageFailure(
        error, STAGE_ADAPTER_PARSE, null, null,
        ResourceErrorCategory.PARSE_ERROR, 'invalid url: ',
      );
    }
    this.emit(STAGE_ADAPTER_PARSE, request, null, null);
    return this.resolveRequest(request, context);
  }

  resolveRequest(request: AssetRequest, context: ResolveContext = createResolveContext()): EngineResult {
    try {
      this.policy.preCheck(request, context);
    } catch (error) {
      return this.stageFailure(
        error, STAGE_POLICY_PRE, request, null,
        ResourceErrorCategory.SECURITY_ERROR, 'preCheck failed: ',
      );
    }
    this.emit(STAGE_POLICY_PRE, request, null, null);

    let resolved: ResolverResult;
    try {
      resolved = this.resolverChain.resolve(request, context, this.observer);
    } catch (error) {
      return this.stageFailure(
        error, STAGE_RESOLVE, request, null,
        ResourceErrorCategory.RESOLUTION_ERROR, 'resolver chain failed: ',
      );
    }

    if (resolved.kind === 'failure') {
      const failure: EngineFailure = engineFailure(resolved.category, resolved.reason, STAGE_RESOLVE);
      this.emit(STAGE_RESOLVE, request, null, failure);
      return failure;
    }
    if (resolved.kind === 'skip') {
      // 'resource not found' 是跨平台契约字面量（Kotlin / iOS 同）。
      const failure: EngineFailure =
        engineFailure(ResourceErrorCategory.RESOLUTION_ERROR, 'resource not found', STAGE_RESOLVE);
      this.emit(STAGE_RESOLVE, request, null, failure);
      return failure;
    }

    return this.resolveHit(request, resolved.descriptor, context);
  }

  private resolveHit(
    request: AssetRequest,
    descriptor: ResourceDescriptor,
    context: ResolveContext,
  ): EngineResult {
    try {
      this.policy.postCheck(request, descriptor, context);
    } catch (error) {
      return this.stageFailure(
        error, STAGE_POLICY_POST, request, descriptor,
        ResourceErrorCategory.SECURITY_ERROR, 'postCheck failed: ',
      );
    }
    this.emit(STAGE_POLICY_POST, request, descriptor, null);

    try {
      const data: ResourceData = this.loader.load(descriptor);
      this.emit(STAGE_LOAD, request, descriptor, null);
      this.emit(STAGE_COMPLETE, request, descriptor, null);
      return engineSuccess(descriptor, data);
    } catch (error) {
      return this.stageFailure(
        error, STAGE_LOAD, request, descriptor,
        ResourceErrorCategory.LOAD_ERROR, 'unexpected load failure: ',
      );
    }
  }

  /**
   * 统一错误处理：ResourceException 保留自己的 category 与 stage（stage 为 null 时才用
   * 当前阶段补齐）；其他异常属于组件内部 bug，归到当前阶段的兜底分类。
   * 对应 Kotlin 的 `stageFailure` 和 iOS 的 `stageFailure`，三端语义等价。
   */
  private stageFailure(
    error: Object,
    stage: string,
    request: AssetRequest | null,
    descriptor: ResourceDescriptor | null,
    fallbackCategory: ResourceErrorCategory,
    fallbackPrefix: string,
  ): EngineResult {
    const failure: EngineFailure = this.toFailure(error, fallbackCategory, stage, fallbackPrefix);
    this.emit(stage, request, descriptor, failure);
    return failure;
  }

  /**
   * ResourceException 保留自己的 category 与 stage（stage 为 null 时才用当前阶段补齐）；
   * 其他异常属于组件内部 bug，归到当前阶段的兜底分类，而不是错误地降级成别的类别。
   *
   * 对应 Kotlin 的两个 catch 分支（`catch (error: ResourceException)` + `catch (error: Exception)`）：
   * ArkTS 的 catch 无法按类型分派，所以在一个 catch 里用 instanceof 判别，语义等价。
   * 兜底前缀（'invalid url: ' 等）逐字对齐 Kotlin 的字符串模板。
   */
  private toFailure(
    error: Object,
    fallbackCategory: ResourceErrorCategory,
    stage: string,
    fallbackPrefix: string,
  ): EngineFailure {
    if (error instanceof ResourceException) {
      return engineFailure(error.category, error.message, error.stage ?? stage);
    }
    return engineFailure(fallbackCategory, fallbackPrefix + (error as Error).message, stage);
  }

  /**
   * 把 EngineFailure（联合成员）投影成 EngineFailureInfo（观测事件的三字段结构）。
   * 两个类型刻意分开，见 api/LocalAssetEngine.ets 的注释。
   */
  private emit(
    stage: string,
    request: AssetRequest | null,
    descriptor: ResourceDescriptor | null,
    failure: EngineFailure | null,
  ): void {
    if (this.observer === null) {
      return;
    }
    this.observer.onStage({
      stage: stage,
      request: request,
      resolverIndex: null,
      resolverResult: null,
      descriptor: descriptor,
      failure: failure === null
        ? null
        : { category: failure.category, reason: failure.reason, stage: failure.stage },
    });
  }
}
