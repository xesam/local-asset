import { describe, it, expect } from '@ohos/hypium';
import { ResolverChain } from '../../main/ets/internal/ResolverChain';
import {
  ResourceResolver,
  ResolverResult,
  resolverHit,
  resolverSkip,
  resolverFailure,
} from '../../main/ets/api/ResourceResolver';
import { AssetRequest, createAssetRequest } from '../../main/ets/model/AssetRequest';
import { ResolveContext, createResolveContext } from '../../main/ets/model/ResolveContext';
import {
  ResourceType,
  ResourceDescriptor,
  bytesSource,
  createResourceDescriptor,
} from '../../main/ets/model/ResourceDescriptor';
import { ResourceErrorCategory } from '../../main/ets/error/ResourceErrorCategory';
import { EngineObserver, EngineStageEvent, STAGE_RESOLVE } from '../../main/ets/api/EngineObserver';

/**
 * 链的职责只有两件事：顺序与短路。只断言返回值的测试无法区分
 * 「后面的 resolver 被正确跳过」与「它其实跑了但返回值恰好被覆盖」，
 * 所以每个 resolver 都把自己的名字追加到共享 log，断言落在调用记录上。
 */
class RecordingResolver implements ResourceResolver {
  readonly name: string;
  private readonly outcome: ResolverResult;
  private readonly log: string[];

  constructor(name: string, outcome: ResolverResult, log: string[]) {
    this.name = name;
    this.outcome = outcome;
    this.log = log;
  }

  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    this.log.push(this.name);
    return this.outcome;
  }
}

/** 收集全部 STAGE_RESOLVE 事件，供顺序/下标/结果断言使用。 */
class RecordingObserver implements EngineObserver {
  readonly events: EngineStageEvent[] = [];

  onStage(event: EngineStageEvent): void {
    this.events.push(event);
  }
}

function sampleRequest(): AssetRequest {
  return createAssetRequest({
    scheme: 'local-asset',
    namespace: 'demo',
    identifier: 'asset-1',
    path: '/asset-1',
  });
}

function sampleDescriptor(id: string): ResourceDescriptor {
  return createResourceDescriptor({
    id: id,
    namespace: 'demo',
    type: ResourceType.DYNAMIC,
    source: bytesSource(new Uint8Array([1, 2, 3])),
    createdAtMillis: 0,
  });
}

export default function resolverChainTest() {
  describe('resolverChainTest', () => {
    it('returns the first hit and short-circuits the rest', 0, () => {
      const log: string[] = [];
      const chain = new ResolverChain([
        new RecordingResolver('a', resolverHit(sampleDescriptor('from-a')), log),
        new RecordingResolver('b', resolverHit(sampleDescriptor('from-b')), log),
      ]);
      const result = chain.resolve(sampleRequest(), createResolveContext());
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        expect(result.descriptor.id).assertEqual('from-a');
      }
      expect(log.length).assertEqual(1);
      expect(log[0]).assertEqual('a');
    });

    it('continues past skip to the next resolver', 0, () => {
      const log: string[] = [];
      const chain = new ResolverChain([
        new RecordingResolver('a', resolverSkip(), log),
        new RecordingResolver('b', resolverHit(sampleDescriptor('from-b')), log),
      ]);
      const result = chain.resolve(sampleRequest(), createResolveContext());
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        expect(result.descriptor.id).assertEqual('from-b');
      }
      expect(log.length).assertEqual(2);
      expect(log[0]).assertEqual('a');
      expect(log[1]).assertEqual('b');
    });

    it('short-circuits on failure without running later resolvers', 0, () => {
      const log: string[] = [];
      const chain = new ResolverChain([
        new RecordingResolver(
          'a',
          resolverFailure(ResourceErrorCategory.RESOLUTION_ERROR, 'resource expired'),
          log,
        ),
        new RecordingResolver('b', resolverHit(sampleDescriptor('from-b')), log),
      ]);
      const result = chain.resolve(sampleRequest(), createResolveContext());
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category).assertEqual(ResourceErrorCategory.RESOLUTION_ERROR);
        expect(result.reason).assertEqual('resource expired');
      }
      expect(log.length).assertEqual(1);
      expect(log[0]).assertEqual('a');
    });

    it('returns skip when every resolver skips', 0, () => {
      const log: string[] = [];
      const chain = new ResolverChain([
        new RecordingResolver('a', resolverSkip(), log),
        new RecordingResolver('b', resolverSkip(), log),
      ]);
      const result = chain.resolve(sampleRequest(), createResolveContext());
      expect(result.kind).assertEqual('skip');
      expect(log.length).assertEqual(2);
      expect(log[0]).assertEqual('a');
      expect(log[1]).assertEqual('b');
    });

    it('returns skip for an empty chain', 0, () => {
      const chain = new ResolverChain([]);
      const result = chain.resolve(sampleRequest(), createResolveContext());
      expect(result.kind).assertEqual('skip');
    });

    it('emits one STAGE_RESOLVE event per executed resolver, in order', 0, () => {
      const log: string[] = [];
      const observer = new RecordingObserver();
      const chain = new ResolverChain([
        new RecordingResolver('a', resolverSkip(), log),
        new RecordingResolver('b', resolverHit(sampleDescriptor('from-b')), log),
        new RecordingResolver('c', resolverHit(sampleDescriptor('from-c')), log),
      ]);
      chain.resolve(sampleRequest(), createResolveContext(), observer);

      // 只发两条：短路掉的 'c' 不产生事件。断言条数而非「>=1」，
      // 才能区分「每个 resolver 一条」与「整条链一条」。
      expect(observer.events.length).assertEqual(2);
      expect(observer.events[0].stage).assertEqual(STAGE_RESOLVE);
      expect(observer.events[0].resolverIndex).assertEqual(0);
      expect((observer.events[0].resolverResult as ResolverResult).kind).assertEqual('skip');
      // skip 事件不带 descriptor
      expect(observer.events[0].descriptor).assertNull();
      expect(observer.events[0].failure).assertNull();
      expect((observer.events[0].request as AssetRequest).identifier).assertEqual('asset-1');

      expect(observer.events[1].resolverIndex).assertEqual(1);
      expect((observer.events[1].resolverResult as ResolverResult).kind).assertEqual('hit');
      // hit 事件把 descriptor 提升到事件字段上
      expect((observer.events[1].descriptor as ResourceDescriptor).id).assertEqual('from-b');
    });

    it('emits an event for the failing resolver before short-circuiting', 0, () => {
      const log: string[] = [];
      const observer = new RecordingObserver();
      const chain = new ResolverChain([
        new RecordingResolver(
          'a',
          resolverFailure(ResourceErrorCategory.RESOLUTION_ERROR, 'resource expired'),
          log,
        ),
        new RecordingResolver('b', resolverHit(sampleDescriptor('from-b')), log),
      ]);
      chain.resolve(sampleRequest(), createResolveContext(), observer);

      expect(observer.events.length).assertEqual(1);
      expect((observer.events[0].resolverResult as ResolverResult).kind).assertEqual('failure');
      expect(observer.events[0].descriptor).assertNull();
      // ResolverChain 只报告事实，不把 resolver 的 failure 翻译成 event.failure ——
      // 那是引擎层（DefaultLocalAssetEngine）的职责。
      expect(observer.events[0].failure).assertNull();
    });

    it('emits nothing when the chain is empty', 0, () => {
      const observer = new RecordingObserver();
      const chain = new ResolverChain([]);
      expect(chain.resolve(sampleRequest(), createResolveContext(), observer).kind).assertEqual('skip');
      expect(observer.events.length).assertEqual(0);
    });
  });
}
