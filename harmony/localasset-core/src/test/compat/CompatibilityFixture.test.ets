import { describe, it, expect } from '@ohos/hypium';
import { readJsonText } from './FixtureReader';
import { FIXTURE_ROOT } from './FixtureRoot.generated';
import { DefaultLocalAssetSchemeAdapter } from '../../main/ets/engine/DefaultLocalAssetSchemeAdapter';
import { decideCache } from '../../main/ets/cache/ResourceCachePolicy';
import {
  ResourceType,
  bytesSource,
  createResourceDescriptor,
} from '../../main/ets/model/ResourceDescriptor';
import { ResourceErrorCategory } from '../../main/ets/error/ResourceErrorCategory';
import { ResourceException } from '../../main/ets/error/ResourceException';
import { LocalAssetBuilder } from '../../main/ets/api/LocalAsset';
import { ResourceResolver, ResolverResult, resolverSkip } from '../../main/ets/api/ResourceResolver';
import { AssetRequest } from '../../main/ets/model/AssetRequest';
import { ResolveContext } from '../../main/ets/model/ResolveContext';
import { STAGE_ADAPTER_PARSE } from '../../main/ets/api/EngineObserver';

/**
 * 跨端共享 fixture 的验收（design.md §6.1）：docs/compatibility-fixtures/*.json 是
 * Android / iOS / harmony 三端共用的行为契约，Android 侧由 CompatibilityFixtureTest.kt 消费。
 *
 * 路径来源：`FIXTURE_ROOT` 由 harmony/hvigorfile.ts 在构建时生成（见该文件顶部的长注释）。
 * 简述原因：ArkTS 测试沙箱里相对路径恒不可用（accessSync 一律 false、相对路径写文件抛
 * `Operation not permitted`、listFileSync 不可调用、getEnvironmentVar 恒为空串），
 * 只能吃绝对路径；而绝对路径不能进仓库，于是交给跑在 Node 上下文的 hvigorfile 生成。
 * fixture 文件读取逻辑抽到了 `FixtureReader.ets`，见其注释。
 */

interface FixtureExpectation {
  category?: string;
  scheme?: string;
  namespace?: string;
  identifier?: string;
  query?: Record<string, string>;
  resolution?: string;
  errorCategory?: string;
  resolverExecuted?: boolean;
  cacheControl?: string;
  etag?: string;
}

interface FixtureInput {
  url?: string;
  type?: string;
  source?: string;
  id?: string;
  size?: number;
  maxAgeSeconds?: number;
}

interface FixtureCase {
  name: string;
  input: FixtureInput;
  expected: FixtureExpectation;
}

function loadCases(fileName: string): FixtureCase[] {
  return JSON.parse(readJsonText(fileName)) as FixtureCase[];
}

function findCase(cases: FixtureCase[], name: string): FixtureCase {
  for (const item of cases) {
    if (item.name === name) {
      return item;
    }
  }
  throw new Error('fixture case not found: ' + name);
}

/** 记录被调用次数，用于实证 fixture 的 `resolverExecuted: false`。 */
class SpyResolver implements ResourceResolver {
  invocations: number = 0;

  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    this.invocations += 1;
    return resolverSkip();
  }
}

export default function compatibilityFixtureTest() {
  describe('compatibilityFixtureTest', () => {
    /**
     * 先钉住"文件确实读到了"。缺了这一条，后面每个 findCase 抛的
     * "fixture case not found" 既可能是解析行为不符，也可能只是文件根本没读进来。
     */
    it('loads the shared fixture files from the generated absolute root', 0, () => {
      expect(FIXTURE_ROOT.endsWith('/docs/compatibility-fixtures')).assertTrue();
      const routing = loadCases('basic-routing.json');
      const cache = loadCases('cache-headers.json');
      expect(routing.length).assertEqual(2);
      expect(cache.length).assertEqual(4);
    });

    it('parses the basic-routing fixture url the same way as Android and iOS', 0, () => {
      const cases = loadCases('basic-routing.json');
      const fixture = findCase(cases, 'parse-basic-local-asset-url');
      const request = new DefaultLocalAssetSchemeAdapter().parse(fixture.input.url as string);

      // 断言方向是 fixture → 实现：期望值一律取自 JSON，不在测试里另写一份字面量，
      // 否则改坏实现的同时改坏测试字面量仍会绿。
      expect(fixture.expected.category).assertEqual('parse');
      expect(request.scheme).assertEqual(fixture.expected.scheme);
      expect(request.namespace).assertEqual(fixture.expected.namespace);
      expect(request.identifier).assertEqual(fixture.expected.identifier);

      // query 也是契约的一部分，同样逐条从 fixture 取（键与值都不硬编码），
      // 这样 fixture 里增删一个 query 键，测试会跟着变严/变松，而不会悄悄漂移。
      const expectedQuery = fixture.expected.query as Record<string, string>;
      const expectedKeys = Object.keys(expectedQuery);
      expect(expectedKeys.length > 0).assertTrue();
      expect(request.query.size).assertEqual(expectedKeys.length);
      for (const key of expectedKeys) {
        expect(request.query.get(key)).assertEqual(expectedQuery[key]);
      }
    });

    /**
     * 该用例只覆盖 SchemeAdapter：URL 在解析阶段就被拒，链上的 resolver 一个都跑不到。
     * fixture 的 `resolverExecuted: false` 用一个间谍 resolver 实证 —— 否则那一条期望
     * 只是"由构造方式必然成立"，等于没测。
     */
    it('rejects the invalid fixture url at parse time without running any resolver', 0, () => {
      const cases = loadCases('basic-routing.json');
      const fixture = findCase(cases, 'reject-invalid-local-asset-url');
      expect(fixture.expected.category).assertEqual('parse');
      expect(fixture.expected.resolution).assertEqual('failure');
      expect(fixture.expected.errorCategory).assertEqual('parse_error');
      expect(fixture.expected.resolverExecuted).assertFalse();

      // 直接调 adapter：确认抛的是 PARSE_ERROR。
      let thrown: ResourceException | null = null;
      try {
        new DefaultLocalAssetSchemeAdapter().parse(fixture.input.url as string);
      } catch (error) {
        thrown = error as ResourceException;
      }
      expect(thrown !== null).assertTrue();
      if (thrown !== null) {
        expect(thrown.category).assertEqual(ResourceErrorCategory.PARSE_ERROR);
      }

      // 再经完整引擎跑一遍，用间谍 resolver 实证 resolverExecuted === false。
      const spy = new SpyResolver();
      const localAsset = new LocalAssetBuilder().addResolver(spy).build();
      const result = localAsset.engine.resolveUrl(fixture.input.url as string);
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category).assertEqual(ResourceErrorCategory.PARSE_ERROR);
        expect(result.stage).assertEqual(STAGE_ADAPTER_PARSE);
      }
      expect(spy.invocations).assertEqual(0);
    });

    it('emits the cache headers the shared fixture expects', 0, () => {
      const cases = loadCases('cache-headers.json');

      // static-bytes-cacheable
      const staticFixture = findCase(cases, 'static-bytes-cacheable');
      const staticBytes = createResourceDescriptor({
        id: staticFixture.input.id as string,
        namespace: 'demo',
        type: ResourceType.STATIC,
        source: bytesSource(new Uint8Array(staticFixture.input.size as number)),
        createdAtMillis: 0,
      });
      const staticDecision = decideCache(staticBytes);
      expect(staticDecision.cacheControl).assertEqual(staticFixture.expected.cacheControl);
      expect(staticDecision.etag).assertEqual(staticFixture.expected.etag);

      // dynamic-bytes-no-store
      const dynamicFixture = findCase(cases, 'dynamic-bytes-no-store');
      const dynamicBytes = createResourceDescriptor({
        id: dynamicFixture.input.id as string,
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array(dynamicFixture.input.size as number)),
        createdAtMillis: 0,
      });
      const dynamicDecision = decideCache(dynamicBytes);
      expect(dynamicDecision.cacheControl).assertEqual(dynamicFixture.expected.cacheControl);
      expect(dynamicDecision.etag).assertEqual(dynamicFixture.expected.etag);

      // static-bytes-custom-max-age
      const customFixture = findCase(cases, 'static-bytes-custom-max-age');
      const customDecision = decideCache(staticBytes, customFixture.input.maxAgeSeconds as number);
      expect(customDecision.cacheControl).assertEqual(customFixture.expected.cacheControl);
      expect(customDecision.etag).assertEqual(customFixture.expected.etag);

      // static-stream-weak-etag：**刻意跳过，不是遗漏**。
      // 该用例的 input.source 是 "stream"，描述 Android/iOS 的 ResourceSource.Stream 来源
      // （etag 形如 W/"<id>"）。harmony 侧的 ResourceSource 只有 bytes/filePath 两个变体
      // （见 model/ResourceDescriptor.ets 与 `docs/design.md` §9.3），刻意不实现 Stream，
      // 因此本平台没有能产生该 etag 的合法输入 —— 不伪造一个 Stream 来凑这条断言。
      // 下面这条断言把"跳过"本身钉死：一旦 harmony 将来引入 Stream 来源，
      // 这条会红，提醒把该用例补进上面的断言列表。
      const streamFixture = findCase(cases, 'static-stream-weak-etag');
      expect(streamFixture.input.source).assertEqual('stream');
      expect(streamFixture.expected.etag).assertEqual('W/"cdn.demo.local:/pkg/home.css"');
    });
  });
}
