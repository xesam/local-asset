import { describe, it, expect } from '@ohos/hypium';
import { ResourceErrorCategory } from '../../main/ets/error/ResourceErrorCategory';
import { ResourceException } from '../../main/ets/error/ResourceException';
import { createAssetRequest } from '../../main/ets/model/AssetRequest';
import { createResolveContext } from '../../main/ets/model/ResolveContext';
import { ResourceType, ResourceScope } from '../../main/ets/model/ResourceDescriptor';

export default function modelContractTest() {
  describe('modelContractTest', () => {
    it('createAssetRequest keeps all fields', 0, () => {
      const query = new Map<string, string>();
      query.set('id', 'home');
      const request = createAssetRequest({
        scheme: 'local-asset',
        namespace: 'image',
        identifier: 'logo',
        path: '/logo',
        query: query,
      });
      expect(request.scheme).assertEqual('local-asset');
      expect(request.namespace).assertEqual('image');
      expect(request.identifier).assertEqual('logo');
      expect(request.path).assertEqual('/logo');
      expect(request.query.get('id')).assertEqual('home');
      expect(request.fragment).assertNull();
    });

    it('createAssetRequest rejects when identifier and path are both null', 0, () => {
      let threw = false;
      try {
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'image',
          identifier: null,
          path: null,
        });
      } catch (error) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('createResolveContext defaults every scope to null', 0, () => {
      const context = createResolveContext();
      expect(context.engineScope).assertNull();
      expect(context.callerScope).assertNull();
      expect(context.pageScope).assertNull();
      expect(context.sessionScope).assertNull();
      expect(context.requestMetadata.size).assertEqual(0);
    });

    it('ResourceException carries category and stage', 0, () => {
      const error = new ResourceException(
        ResourceErrorCategory.SECURITY_ERROR,
        'namespace is not allowed',
        'policy_pre',
      );
      expect(error.category).assertEqual('SECURITY_ERROR');
      expect(error.message).assertEqual('namespace is not allowed');
      expect(error.stage).assertEqual('policy_pre');
      expect(error instanceof Error).assertTrue();
    });

    /**
     * 断言字面量而非枚举自身：这些字符串是跨平台线格式契约。
     * DefaultPolicy 用 scope 的字符串值拼错误消息，compatibility-fixtures
     * 里的 errorCategory 也直接锚定这些值。枚举对枚举的比较永远不会失败。
     */
    it('ResourceErrorCategory members carry the agreed wire values', 0, () => {
      expect(ResourceErrorCategory.PARSE_ERROR).assertEqual('PARSE_ERROR');
      expect(ResourceErrorCategory.RESOLUTION_ERROR).assertEqual('RESOLUTION_ERROR');
      expect(ResourceErrorCategory.LOAD_ERROR).assertEqual('LOAD_ERROR');
      expect(ResourceErrorCategory.SECURITY_ERROR).assertEqual('SECURITY_ERROR');
    });

    it('ResourceType members carry the agreed wire values', 0, () => {
      expect(ResourceType.STATIC).assertEqual('STATIC');
      expect(ResourceType.DYNAMIC).assertEqual('DYNAMIC');
    });

    it('ResourceScope members carry the agreed wire values', 0, () => {
      expect(ResourceScope.ENGINE).assertEqual('ENGINE');
      expect(ResourceScope.PAGE).assertEqual('PAGE');
      expect(ResourceScope.SESSION).assertEqual('SESSION');
    });
  });
}
