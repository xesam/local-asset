import { describe, it, expect } from '@ohos/hypium';
import { DefaultLocalAssetSchemeAdapter } from '../../main/ets/engine/DefaultLocalAssetSchemeAdapter';
import { ResourceException } from '../../main/ets/error/ResourceException';
import { ResourceErrorCategory } from '../../main/ets/error/ResourceErrorCategory';

export default function defaultLocalAssetSchemeAdapterTest() {
  describe('defaultLocalAssetSchemeAdapterTest', () => {
    it('canHandle accepts local-asset scheme only', 0, () => {
      const adapter = new DefaultLocalAssetSchemeAdapter();
      expect(adapter.canHandle('local-asset://image/logo')).assertTrue();
      expect(adapter.canHandle('https://example.com/logo.png')).assertFalse();
      expect(adapter.canHandle('not a url at all')).assertFalse();
    });

    it('parses namespace, identifier, path and query', 0, () => {
      const adapter = new DefaultLocalAssetSchemeAdapter();
      const request = adapter.parse('local-asset://image/logo?id=home&theme=dark');
      expect(request.scheme).assertEqual('local-asset');
      expect(request.namespace).assertEqual('image');
      expect(request.identifier).assertEqual('logo');
      expect(request.path).assertEqual('/logo');
      expect(request.query.get('id')).assertEqual('home');
      expect(request.query.get('theme')).assertEqual('dark');
    });

    it('parses nested path and keeps last segment as identifier', 0, () => {
      const adapter = new DefaultLocalAssetSchemeAdapter();
      const request = adapter.parse('local-asset://cdn.demo.local/pkg/css/home.css');
      expect(request.namespace).assertEqual('cdn.demo.local');
      expect(request.path).assertEqual('/pkg/css/home.css');
      expect(request.identifier).assertEqual('home.css');
    });

    it('url-decodes query values', 0, () => {
      const adapter = new DefaultLocalAssetSchemeAdapter();
      const request = adapter.parse('local-asset://image/logo?name=a%20b%26c');
      expect(request.query.get('name')).assertEqual('a b&c');
    });

    it('keeps fragment when present', 0, () => {
      const adapter = new DefaultLocalAssetSchemeAdapter();
      const request = adapter.parse('local-asset://image/logo#section');
      expect(request.fragment).assertEqual('section');
    });

    it('rejects url without namespace as PARSE_ERROR', 0, () => {
      const adapter = new DefaultLocalAssetSchemeAdapter();
      let caught: ResourceException | null = null;
      try {
        adapter.parse('local-asset:///invalid');
      } catch (error) {
        caught = error as ResourceException;
      }
      expect(caught !== null).assertTrue();
      expect((caught as ResourceException).category).assertEqual(ResourceErrorCategory.PARSE_ERROR);
    });

    it('rejects unsupported scheme as PARSE_ERROR', 0, () => {
      const adapter = new DefaultLocalAssetSchemeAdapter();
      let caught: ResourceException | null = null;
      try {
        adapter.parse('https://example.com/logo.png');
      } catch (error) {
        caught = error as ResourceException;
      }
      expect(caught !== null).assertTrue();
      expect((caught as ResourceException).category).assertEqual(ResourceErrorCategory.PARSE_ERROR);
    });

    it('rejects url without path as PARSE_ERROR', 0, () => {
      const adapter = new DefaultLocalAssetSchemeAdapter();
      let caught: ResourceException | null = null;
      try {
        adapter.parse('local-asset://image');
      } catch (error) {
        caught = error as ResourceException;
      }
      expect(caught !== null).assertTrue();
      expect((caught as ResourceException).category).assertEqual(ResourceErrorCategory.PARSE_ERROR);
      expect((caught as ResourceException).message).assertEqual('missing path');
    });

    /**
     * 以下用例的期望值全部来自对参考实现的实测，而非推断：
     * java.net.URI("local-asset://image/a%20b/c.png").getPath() == "/a b/c.png"，
     * iOS URLComponents(string:).path 同为 "/a b/c.png"。
     */
    it('percent-decodes the path like java.net.URI getPath', 0, () => {
      const adapter = new DefaultLocalAssetSchemeAdapter();
      const request = adapter.parse('local-asset://image/a%20b/c.png');
      expect(request.path).assertEqual('/a b/c.png');
      expect(request.identifier).assertEqual('c.png');
    });

    /**
     * %2F 解码后 *会* 产生新的分段边界 —— 这是实测结论，与直觉相反：
     * Kotlin 在解码后的 path 上跑 substringAfterLast('/')，iOS 在 comps.path 上 split，
     * 两者对 '/a%2Fb' 都得到 path='/a/b' 且 identifier='b'。
     * 因此实现必须「先整体解码，再分段」；反过来（先分段再逐段解码）会得到 identifier='a/b'，
     * 那才是与 Android/iOS 不一致的写法。
     */
    it('lets a decoded %2F create a segment boundary, matching both references', 0, () => {
      const adapter = new DefaultLocalAssetSchemeAdapter();
      const request = adapter.parse('local-asset://image/a%2Fb');
      expect(request.path).assertEqual('/a/b');
      expect(request.identifier).assertEqual('b');

      const nested = adapter.parse('local-asset://image/a%20b/c%2Fd');
      expect(nested.path).assertEqual('/a b/c/d');
      expect(nested.identifier).assertEqual('d');
    });

    it('accepts a bare trailing slash with null identifier', 0, () => {
      const adapter = new DefaultLocalAssetSchemeAdapter();
      const request = adapter.parse('local-asset://image/');
      expect(request.namespace).assertEqual('image');
      expect(request.path).assertEqual('/');
      expect(request.identifier).assertNull();
    });

    it('percent-decodes the fragment', 0, () => {
      const adapter = new DefaultLocalAssetSchemeAdapter();
      expect(adapter.parse('local-asset://image/logo#a%20b').fragment).assertEqual('a b');
    });

    /**
     * '+' 只在 query 里表示空格（HTML form 语义，对齐 URLDecoder.decode）；
     * path 与 fragment 保留字面 '+'，实测 Kotlin uri.path/uri.fragment 与 iOS 均如此。
     */
    it('keeps a literal plus in path and fragment but decodes it in query', 0, () => {
      const adapter = new DefaultLocalAssetSchemeAdapter();
      const request = adapter.parse('local-asset://image/a+b?q=a+b#f+g');
      expect(request.path).assertEqual('/a+b');
      expect(request.fragment).assertEqual('f+g');
      expect(request.query.get('q')).assertEqual('a b');
    });

    /**
     * 畸形转义：java.net.URI 直接抛 URISyntaxException，Kotlin 归一为 'invalid url'。
     * 注意 iOS 的 URLComponents 反而容忍 '%ZZ'（path 原样保留），此处选择与 Android 对齐。
     */
    it('maps malformed percent escapes to PARSE_ERROR invalid url', 0, () => {
      const adapter = new DefaultLocalAssetSchemeAdapter();
      let caught: ResourceException | null = null;
      try {
        adapter.parse('local-asset://image/a%ZZb');
      } catch (error) {
        caught = error as ResourceException;
      }
      expect(caught !== null).assertTrue();
      expect((caught as ResourceException).category).assertEqual(ResourceErrorCategory.PARSE_ERROR);
      expect((caught as ResourceException).message).assertEqual('invalid url');
    });
  });
}
