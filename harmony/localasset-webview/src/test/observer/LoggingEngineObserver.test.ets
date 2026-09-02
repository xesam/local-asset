import { describe, it, expect } from '@ohos/hypium';
import {
  LoggingEngineObserver,
  LogSink,
  LOG_LEVEL_DEBUG,
  LOG_LEVEL_WARN,
} from '../../../Index';
import {
  LocalAssetBuilder,
  createResourceDescriptor,
  bytesSource,
  ResourceType,
  ResourceErrorCategory,
  EngineStageEvent,
  STAGE_ADAPTER_PARSE,
  STAGE_COMPLETE,
} from 'io.github.xesam.harmony.localasset.core';

/**
 * 本文件与 SchemeRequestHandler.test.ets 一样兼作 **barrel 守卫**：顶部从
 * `../../../Index` 具名导入的符号若在 Index.ets 漏导，编译期即报错。
 *
 * ⚠️ 本文件是 ArkWeb 适配层一侧 **唯一**能真正断言行为的测试。与它同层的
 * `LocalAssetSchemeHandler` 触碰真实 ArkWeb 类型（`webview.WebSchemeHandler` 等），
 * ArkWeb 没有 Robolectric 等价物，`hvigorw test` 对它只能做到"编译通过"，
 * 真实行为要到 sample 应用真机验收才能确认（见该文件头部的验收清单注释）。
 */

/** 收集 (level, tag, message) 三元组的测试用 sink。 */
class RecordingSink {
  readonly levels: number[] = [];
  readonly tags: string[] = [];
  readonly messages: string[] = [];

  get asSink(): LogSink {
    return (level: number, tag: string, message: string): void => {
      this.levels.push(level);
      this.tags.push(tag);
      this.messages.push(message);
    };
  }

  /** 第一条包含 needle 的消息；没有则返回 null。 */
  find(needle: string): string | null {
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].includes(needle)) {
        return this.messages[i];
      }
    }
    return null;
  }

  levelOf(needle: string): number {
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].includes(needle)) {
        return this.levels[i];
      }
    }
    return -1;
  }
}

/** 注册了一条 DYNAMIC 资源、并挂上 recording observer 的引擎。 */
function runPipeline(sink: RecordingSink, url: string): string {
  const localAsset = new LocalAssetBuilder()
    .setObserver(new LoggingEngineObserver('LocalAssetTest', sink.asSink))
    .build();
  localAsset.register(createResourceDescriptor({
    id: 'asset-1',
    namespace: 'demo',
    type: ResourceType.DYNAMIC,
    source: bytesSource(new Uint8Array([1])),
    createdAtMillis: 0,
  }));
  return localAsset.engine.resolveUrl(url).kind;
}

export default function loggingEngineObserverTest() {
  describe('loggingEngineObserverTest', () => {
    /* ---------- 冒烟：默认 sink（真实 hilog）不得抛 ---------- */

    /**
     * 默认 sink 直连 hilog。这里不断言输出内容（拿不到 hilog 缓冲区），
     * 只钉住"接入观测器不会让流水线炸掉"这一条 —— observer 的契约是
     * 不得对流水线产生副作用（core EngineObserver.ets 的注释）。
     */
    it('observes a full pipeline without throwing', 0, () => {
      const localAsset = new LocalAssetBuilder()
        .setObserver(new LoggingEngineObserver('LocalAssetTest'))
        .build();
      localAsset.register(createResourceDescriptor({
        id: 'asset-1',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1])),
        createdAtMillis: 0,
      }));
      expect(localAsset.engine.resolveUrl('local-asset://demo/asset-1').kind).assertEqual('success');
    });

    it('observes a failing pipeline without throwing', 0, () => {
      const localAsset = new LocalAssetBuilder()
        .setObserver(new LoggingEngineObserver('LocalAssetTest'))
        .build();
      expect(localAsset.engine.resolveUrl('local-asset://demo/missing').kind).assertEqual('failure');
    });

    /** 观测器不得改写流水线结果 —— 上面两条已隐含，这里显式钉住成功路径的 body。 */
    it('does not perturb the engine outcome', 0, () => {
      const sink = new RecordingSink();
      expect(runPipeline(sink, 'local-asset://demo/asset-1')).assertEqual('success');
      expect(sink.messages.length > 0).assertTrue();
    });

    /* ---------- 格式：与 Android / iOS 的字段拼装逐段对齐 ---------- */

    it('prefixes every line with the stage', 0, () => {
      const sink = new RecordingSink();
      runPipeline(sink, 'local-asset://demo/asset-1');
      for (let i = 0; i < sink.messages.length; i++) {
        expect(sink.messages[i].startsWith('stage=')).assertTrue();
      }
    });

    /** 成功流水线必须走到终态事件；漏发 complete 说明引擎或观测器串错了。 */
    it('records the terminal complete stage on success', 0, () => {
      const sink = new RecordingSink();
      runPipeline(sink, 'local-asset://demo/asset-1');
      const line = sink.find('stage=' + STAGE_COMPLETE);
      expect(line !== null).assertTrue();
      expect(line !== null && line.includes('descriptor=asset-1')).assertTrue();
    });

    /** request 非空的事件带上 namespace，对齐 Android 的 `ns=` / iOS 的 `ns=`。 */
    it('includes the namespace when the event carries a request', 0, () => {
      const sink = new RecordingSink();
      runPipeline(sink, 'local-asset://demo/asset-1');
      expect(sink.find('ns=demo') !== null).assertTrue();
    });

    /**
     * adapter_parse 失败的事件 request 为 null —— 此时不得凭空拼出 ns= 段。
     * 这条同时钉住"字段按存在性拼接"而不是无脑输出占位符。
     */
    it('omits the namespace when the request is absent', 0, () => {
      const sink = new RecordingSink();
      runPipeline(sink, 'https://example.com/logo.png');
      const line = sink.find('stage=' + STAGE_ADAPTER_PARSE);
      expect(line !== null).assertTrue();
      expect(line !== null && line.includes('ns=')).assertFalse();
    });

    /** resolver 事件带下标与决策 kind（ArkTS 拿不到稳定类名，用 kind 代替 Android 的类名）。 */
    it('records each resolver index and decision', 0, () => {
      const sink = new RecordingSink();
      runPipeline(sink, 'local-asset://demo/asset-1');
      // 链序固定：HandleRegistryResolver(0) skip → RegistryResolver(1) hit。
      expect(sink.find('resolver[0]=skip') !== null).assertTrue();
      expect(sink.find('resolver[1]=hit') !== null).assertTrue();
    });

    /** 失败三要素（category / stage / reason）必须全部出现，否则日志追不到因。 */
    it('records category, stage and reason on failure', 0, () => {
      const sink = new RecordingSink();
      expect(runPipeline(sink, 'local-asset://demo/missing')).assertEqual('failure');
      const line = sink.find('failure[');
      expect(line !== null).assertTrue();
      expect(line !== null && line.includes('failure[RESOLUTION_ERROR/resolve]')).assertTrue();
      expect(line !== null && line.includes('resource not found')).assertTrue();
    });

    /** failure.stage 为 null 时补 '-'，不得漏成 'failure[CAT/null]' 或 'failure[CAT/undefined]'。 */
    it('substitutes a dash for a null failure stage', 0, () => {
      const sink = new RecordingSink();
      const observer = new LoggingEngineObserver('LocalAssetTest', sink.asSink);
      const event: EngineStageEvent = {
        stage: 'resolve',
        request: null,
        resolverIndex: null,
        resolverResult: null,
        descriptor: null,
        failure: { category: ResourceErrorCategory.SECURITY_ERROR, reason: 'boom', stage: null },
      };
      observer.onStage(event);
      expect(sink.messages[0].includes('failure[SECURITY_ERROR/-] boom')).assertTrue();
    });

    /* ---------- 级别：失败 warn，其余 debug ---------- */

    /**
     * 失败事件抬到 warn。全部打成 debug 会让失败在真机 hilog 的默认过滤下消失 ——
     * 这正是 SchemeRequestHandler.onFailure 存在的理由，但日志侧也不该自废武功。
     */
    it('logs failures at warn level', 0, () => {
      const sink = new RecordingSink();
      runPipeline(sink, 'local-asset://demo/missing');
      expect(sink.levelOf('failure[')).assertEqual(LOG_LEVEL_WARN);
    });

    it('logs non-failure stages at debug level', 0, () => {
      const sink = new RecordingSink();
      runPipeline(sink, 'local-asset://demo/asset-1');
      expect(sink.levelOf('stage=' + STAGE_COMPLETE)).assertEqual(LOG_LEVEL_DEBUG);
    });

    /* ---------- tag ---------- */

    it('passes the configured tag through to the sink', 0, () => {
      const sink = new RecordingSink();
      runPipeline(sink, 'local-asset://demo/asset-1');
      expect(sink.tags[0]).assertEqual('LocalAssetTest');
    });

    /** 缺省 tag 与 Android 的 DEFAULT_TAG / iOS 的 category 逐字一致。 */
    it('defaults the tag to LocalAssetObserver', 0, () => {
      const sink = new RecordingSink();
      const observer = new LoggingEngineObserver(undefined, sink.asSink);
      const event: EngineStageEvent = {
        stage: 'complete',
        request: null,
        resolverIndex: null,
        resolverResult: null,
        descriptor: null,
        failure: null,
      };
      observer.onStage(event);
      expect(sink.tags[0]).assertEqual('LocalAssetObserver');
    });

    /**
     * sink 抛异常不得炸穿流水线 —— observer 是旁路观测，任何日志故障
     * 都不该把一次正常的资源请求变成失败。对齐 Android 的 runCatching。
     */
    it('swallows sink failures instead of breaking the pipeline', 0, () => {
      const localAsset = new LocalAssetBuilder()
        .setObserver(new LoggingEngineObserver('LocalAssetTest', (): void => {
          throw new Error('sink exploded');
        }))
        .build();
      localAsset.register(createResourceDescriptor({
        id: 'asset-1',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1])),
        createdAtMillis: 0,
      }));
      expect(localAsset.engine.resolveUrl('local-asset://demo/asset-1').kind).assertEqual('success');
    });
  });
}
