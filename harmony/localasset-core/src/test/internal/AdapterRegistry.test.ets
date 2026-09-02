import { describe, it, expect } from '@ohos/hypium';
import { AdapterRegistry } from '../../main/ets/internal/AdapterRegistry';
import { DefaultLocalAssetSchemeAdapter } from '../../main/ets/engine/DefaultLocalAssetSchemeAdapter';
import { SchemeAdapter } from '../../main/ets/api/SchemeAdapter';
import { AssetRequest, createAssetRequest } from '../../main/ets/model/AssetRequest';
import { ResourceException } from '../../main/ets/error/ResourceException';
import { ResourceErrorCategory } from '../../main/ets/error/ResourceErrorCategory';

/**
 * 两个 adapter 对同一个 url 都返回 canHandle=true —— 只有这种形状能在
 * select() 退化成 last-match-wins（例如 adapters.filter(...).pop()）时失败。
 * 只注册一个 adapter、或注册多个但只有一个匹配（Kotlin 参考测试即是后者），
 * 两种写法都无法区分「首个匹配」与「末个匹配」。
 */
class AlwaysMatchingAdapter implements SchemeAdapter {
  readonly tag: string;

  constructor(tag: string) {
    this.tag = tag;
  }

  canHandle(url: string): boolean {
    return true;
  }

  parse(url: string): AssetRequest {
    return createAssetRequest({
      scheme: 'local-asset',
      namespace: this.tag,
      identifier: 'page',
      path: '/page',
    });
  }
}

class NeverMatchingAdapter implements SchemeAdapter {
  canHandle(url: string): boolean {
    return false;
  }

  parse(url: string): AssetRequest {
    throw new ResourceException(ResourceErrorCategory.PARSE_ERROR, 'unreachable');
  }
}

export default function adapterRegistryTest() {
  describe('adapterRegistryTest', () => {
    it('selects the first adapter when several can handle the url', 0, () => {
      const first = new AlwaysMatchingAdapter('first');
      const second = new AlwaysMatchingAdapter('second');
      const registry = new AdapterRegistry([first, second]);

      const selected = registry.select('local-asset://demo/asset-1');

      expect(selected).assertEqual(first);
      // 冗余但直接：把「拿到的是 first 而不是 second」钉在一个可读字段上，
      // 不依赖 assertEqual 对同构对象的比较策略。
      expect((selected as AlwaysMatchingAdapter).tag).assertEqual('first');
    });

    it('skips a non-matching adapter and selects a later match', 0, () => {
      const real = new DefaultLocalAssetSchemeAdapter();
      const registry = new AdapterRegistry([new NeverMatchingAdapter(), real]);
      expect(registry.select('local-asset://demo/asset-1')).assertEqual(real);
    });

    it('selects the adapter that can handle the url', 0, () => {
      const adapter = new DefaultLocalAssetSchemeAdapter();
      const registry = new AdapterRegistry([adapter]);
      expect(registry.select('local-asset://demo/asset-1')).assertEqual(adapter);
    });

    it('throws PARSE_ERROR when no adapter matches', 0, () => {
      const registry = new AdapterRegistry([new DefaultLocalAssetSchemeAdapter()]);
      let caught: ResourceException | null = null;
      try {
        registry.select('https://example.com/logo.png');
      } catch (error) {
        caught = error as ResourceException;
      }
      expect(caught !== null).assertTrue();
      expect((caught as ResourceException).category).assertEqual(ResourceErrorCategory.PARSE_ERROR);
      expect((caught as ResourceException).message).assertEqual('no adapter can handle url');
    });

    it('throws PARSE_ERROR for an empty registry', 0, () => {
      const registry = new AdapterRegistry([]);
      let caught: ResourceException | null = null;
      try {
        registry.select('local-asset://demo/asset-1');
      } catch (error) {
        caught = error as ResourceException;
      }
      expect(caught !== null).assertTrue();
      expect((caught as ResourceException).category).assertEqual(ResourceErrorCategory.PARSE_ERROR);
    });
  });
}
