import { describe, it, expect } from '@ohos/hypium';
import { InMemoryResourceRegistry } from '../../main/ets/registry/InMemoryResourceRegistry';
import {
  ResourceType,
  bytesSource,
  createResourceDescriptor,
  ResourceDescriptor,
} from '../../main/ets/model/ResourceDescriptor';
import { ResourceException } from '../../main/ets/error/ResourceException';
import { ResourceErrorCategory } from '../../main/ets/error/ResourceErrorCategory';

function descriptor(id: string, createdAtMillis: number, ttlMillis: number | null): ResourceDescriptor {
  return createResourceDescriptor({
    id: id,
    namespace: 'demo',
    type: ResourceType.DYNAMIC,
    source: bytesSource(new Uint8Array([1])),
    createdAtMillis: createdAtMillis,
    ttlMillis: ttlMillis,
  });
}

/**
 * 所有用例都注入固定时钟（`() => <常量>`），不读挂钟：TTL 判据是
 * `createdAt + ttl <= now` 的闭区间边界，用 Date.now() 会让 999/1000 这一毫秒
 * 之差变成随机结果。
 */
export default function inMemoryResourceRegistryTest() {
  describe('inMemoryResourceRegistryTest', () => {
    it('registers then looks up a descriptor', 0, () => {
      const registry = new InMemoryResourceRegistry(() => 1000);
      registry.register(descriptor('asset-1', 0, null));
      const result = registry.lookup('asset-1');
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        expect(result.descriptor.id).assertEqual('asset-1');
      }
    });

    it('returns missing for unknown id', 0, () => {
      const registry = new InMemoryResourceRegistry(() => 1000);
      expect(registry.lookup('nope').kind).assertEqual('missing');
    });

    it('returns missing after remove', 0, () => {
      const registry = new InMemoryResourceRegistry(() => 1000);
      registry.register(descriptor('asset-1', 0, null));
      registry.remove('asset-1');
      expect(registry.lookup('asset-1').kind).assertEqual('missing');
    });

    it('rejects duplicate id with RESOLUTION_ERROR', 0, () => {
      const registry = new InMemoryResourceRegistry(() => 1000);
      registry.register(descriptor('asset-1', 0, null));
      let caught: ResourceException | null = null;
      try {
        registry.register(descriptor('asset-1', 0, null));
      } catch (error) {
        caught = error as ResourceException;
      }
      expect(caught !== null).assertTrue();
      expect((caught as ResourceException).category).assertEqual(ResourceErrorCategory.RESOLUTION_ERROR);
      expect((caught as ResourceException).message).assertEqual('duplicate resource id: asset-1');
    });

    it('keeps the first descriptor when a duplicate register is rejected', 0, () => {
      // Kotlin 用 putIfAbsent：冲突时**不覆盖**已存在的条目。若这里写成
      // 先 set 后判重，本用例会看到 keep-me 被 overwrite 掉。
      const registry = new InMemoryResourceRegistry(() => 1000);
      registry.register(descriptor('asset-1', 0, null));
      let rejected = false;
      try {
        registry.register(descriptor('asset-1', 500, 1));
      } catch (error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
      const result = registry.lookup('asset-1');
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        expect(result.descriptor.createdAtMillis).assertEqual(0);
        expect(result.descriptor.ttlMillis).assertNull();
      }
    });

    it('reports expired once ttl elapsed', 0, () => {
      // createdAt=0, ttl=1000 -> 到期判据是 createdAt + ttl <= now
      const registry = new InMemoryResourceRegistry(() => 1000);
      registry.register(descriptor('asset-1', 0, 1000));
      expect(registry.lookup('asset-1').kind).assertEqual('expired');
    });

    it('still hits just before expiry', 0, () => {
      const registry = new InMemoryResourceRegistry(() => 999);
      registry.register(descriptor('asset-1', 0, 1000));
      expect(registry.lookup('asset-1').kind).assertEqual('hit');
    });

    it('cleanup drops only expired entries', 0, () => {
      const registry = new InMemoryResourceRegistry(() => 0);
      registry.register(descriptor('gone', 0, 100));
      registry.register(descriptor('kept', 0, null));
      registry.cleanup(1000);
      expect(registry.lookup('gone').kind).assertEqual('missing');
      expect(registry.lookup('kept').kind).assertEqual('hit');
    });

    it('cleanup honours the same <= boundary as lookup', 0, () => {
      // createdAt+ttl == nowMillis 必须被清掉（闭区间），差 1ms 则留下。
      const registry = new InMemoryResourceRegistry(() => 0);
      registry.register(descriptor('at-boundary', 0, 1000));
      registry.register(descriptor('one-ms-left', 1, 1000));
      registry.cleanup(1000);
      expect(registry.lookup('at-boundary').kind).assertEqual('missing');
      expect(registry.lookup('one-ms-left').kind).assertEqual('hit');
    });

    it('allows re-register after remove', 0, () => {
      const registry = new InMemoryResourceRegistry(() => 1000);
      registry.register(descriptor('asset-1', 0, null));
      registry.remove('asset-1');
      registry.register(descriptor('asset-1', 42, null));
      const result = registry.lookup('asset-1');
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        expect(result.descriptor.createdAtMillis).assertEqual(42);
      }
    });

    it('remove of an unknown id is a no-op', 0, () => {
      const registry = new InMemoryResourceRegistry(() => 1000);
      registry.remove('nope');
      expect(registry.lookup('nope').kind).assertEqual('missing');
    });

    it('lookup re-evaluates the clock on every call', 0, () => {
      // nowProvider 不是构造期快照：同一个 descriptor 先 hit 后 expired。
      let now = 0;
      const registry = new InMemoryResourceRegistry(() => now);
      registry.register(descriptor('asset-1', 0, 1000));
      expect(registry.lookup('asset-1').kind).assertEqual('hit');
      now = 1000;
      expect(registry.lookup('asset-1').kind).assertEqual('expired');
    });

    it('expired entries stay looked-up-able until cleanup', 0, () => {
      // lookup 只报告状态，不做惰性驱逐——Kotlin/iOS 侧亦然（lookup 不写 map）。
      const registry = new InMemoryResourceRegistry(() => 1000);
      registry.register(descriptor('asset-1', 0, 1000));
      expect(registry.lookup('asset-1').kind).assertEqual('expired');
      let caught: ResourceException | null = null;
      try {
        registry.register(descriptor('asset-1', 0, null));
      } catch (error) {
        caught = error as ResourceException;
      }
      expect(caught !== null).assertTrue();
    });
  });
}
