import { ResourceResolver, ResolverResult, resolverSkip } from '../api/ResourceResolver';
import { AssetRequest } from '../model/AssetRequest';
import { ResolveContext } from '../model/ResolveContext';
import { EngineObserver, STAGE_RESOLVE } from '../api/EngineObserver';

/**
 * design.md §3.4：按注册顺序执行，首个 Hit 或 Failure 终止链路，Skip 继续下一个；
 * 全部 Skip（含空链）则返回 Skip。
 *
 * 第三个参数 observer 可选（与 Kotlin 的 `observer: EngineObserver? = null` 对齐）：
 * 每个 resolver 执行后发一次 STAGE_RESOLVE 事件，带上它在链中的下标与决策结果。
 * 事件在短路判断**之前**发出，因此终止链路的那个 resolver 也会被观测到。
 */
export class ResolverChain {
  private readonly resolvers: ResourceResolver[];

  constructor(resolvers: ResourceResolver[]) {
    this.resolvers = resolvers;
  }

  resolve(
    request: AssetRequest,
    context: ResolveContext,
    observer: EngineObserver | null = null,
  ): ResolverResult {
    for (let index = 0; index < this.resolvers.length; index++) {
      const result = this.resolvers[index].resolve(request, context);
      if (observer !== null) {
        observer.onStage({
          stage: STAGE_RESOLVE,
          request: request,
          resolverIndex: index,
          resolverResult: result,
          descriptor: result.kind === 'hit' ? result.descriptor : null,
          failure: null,
        });
      }
      if (result.kind === 'hit' || result.kind === 'failure') {
        return result;
      }
    }
    return resolverSkip();
  }
}
