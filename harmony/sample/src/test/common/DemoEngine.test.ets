import { describe, it, expect } from '@ohos/hypium';
import {
  LocalAssetBuilder,
  DefaultPolicy,
  createResolveContext,
  EngineResult,
  bytesSource,
} from 'io.github.xesam.harmony.localasset.core';
import { RawfileDirectoryResolver } from 'io.github.xesam.harmony.localasset.webview';
import { BannerOverrideResolver } from '../../main/ets/common/OverrideBanner';
import { ErrorProbeResolver } from '../../main/ets/common/ErrorProbes';

/**
 * `DemoEngine` 的装配契约。
 *
 * 八条 sample flow 合并成一个引擎之后，「某个 host 还能不能解析」不再是某个场景页
 * 自己的事 —— 它取决于整条 resolver 链的相互作用。这类回归**编译期发现不了**，
 * ArkUI 页面又没有任何测试手段，于是只能在真机上以「所有图片和 CSS 全都加载不出来」
 * 的形式暴露出来。本文件把装配本身钉死。
 *
 * 这里刻意**不 import DemoEngine**：它的构造函数吃 `UIAbilityContext`，测试沙箱里
 * 没有 Context。改为逐项复刻同一套装配 —— 与 `ErrorProbes.test.ets` 复刻
 * ErrorCategoriesPage 是同一手法。代价是两处要一起改，收益是这条链路终于有断言。
 */

const ENGINE_SCOPE = 'demo-engine';
const TMP_ROOT = '/tmp/localasset-demoengine';

/**
 * rawfile 读取的替身：只认共享 HTML 真正引用的那几条路径，其余一律返回 null。
 *
 * **不要退化成"按扩展名一律返回字节"** —— 那样任何路径都读得到，
 * 「资源不存在时应当失败」这条断言会被替身本身满足掉，测不出东西。
 * 这里的清单与 `shared/demo/` 下的实际文件一一对应。
 */
const RAWFILE_PRESENT: string[] = [
  'demo/static/styles.css',
  'demo/static/app.js',
  'demo/static/images/logo.svg',
  'demo/base/layout.css',
  'demo/base/card.svg',
  'demo/base/banner.svg',
];

function fakeRawfile(path: string): Uint8Array | null {
  return RAWFILE_PRESENT.includes(path) ? new Uint8Array([1, 2, 3, 4]) : null;
}

/**
 * 复刻 `DemoEngine` 的 resolver 链，逐项对应。
 *
 * 顺序即语义：BannerOverrideResolver 必须在 chain.demo.local 的目录 resolver 之前，
 * 否则覆盖演示失效（design.md §3.4）。
 */
function buildDemoEngine() {
  return new LocalAssetBuilder()
    .setPolicy(new DefaultPolicy({ allowedFileRoots: [TMP_ROOT] }))
    .addResolver(new BannerOverrideResolver())
    .addResolver(new ErrorProbeResolver(TMP_ROOT + '/never-created.bin'))
    .addResolver(new RawfileDirectoryResolver({
      host: 'assets.demo.local',
      pathPrefix: '/static',
      rawfileDirectory: 'demo/static',
      readRawfile: fakeRawfile,
    }))
    .addResolver(new RawfileDirectoryResolver({
      host: 'chain.demo.local',
      pathPrefix: '/base',
      rawfileDirectory: 'demo/base',
      readRawfile: fakeRawfile,
    }))
    .addResolver(new RawfileDirectoryResolver({
      host: 'resilient.demo.local',
      pathPrefix: '/static',
      rawfileDirectory: 'demo/static',
      readRawfile: fakeRawfile,
    }))
    .build()
    .engine;
}

function resolve(url: string): EngineResult {
  return buildDemoEngine().resolveUrl(url, createResolveContext({ engineScope: ENGINE_SCOPE }));
}

function assertSuccess(url: string): void {
  const result = resolve(url);
  if (result.kind !== 'success') {
    // 把 category + stage 摊开，否则失败信息只剩一个 'failure' 毫无指向。
    expect(String(result.category) + ' @ ' + (result.stage ?? '-') + ' — ' + result.reason)
      .assertEqual('success');
  }
  expect(result.kind).assertEqual('success');
}

export default function demoEngineTest() {
  describe('DemoEngineAssembly', () => {
    /**
     * 共享 HTML 里逐字出现的三条 URL。这是真机上「图片/CSS 全白」最直接的判据 ——
     * 合并引擎时漏掉任何一条 resolver，或写错 host / pathPrefix，本用例立刻变红。
     */
    it('shared_page_subresources_resolve', 0, () => {
      assertSuccess('local-asset://assets.demo.local/static/styles.css');
      assertSuccess('local-asset://assets.demo.local/static/app.js');
      assertSuccess('local-asset://assets.demo.local/static/images/logo.svg');
    });

    it('resolver_chain_hosts_resolve', 0, () => {
      // 覆盖 resolver 命中（?mode= 驱动动态内容），以及同级路径落到目录 resolver。
      assertSuccess('local-asset://chain.demo.local/base/banner.svg?mode=dark');
      assertSuccess('local-asset://chain.demo.local/base/card.svg');
      assertSuccess('local-asset://chain.demo.local/base/layout.css');
    });

    it('graceful_degradation_host_resolves', 0, () => {
      assertSuccess('local-asset://resilient.demo.local/static/images/logo.svg');
    });

    /**
     * 合并的核心风险：错误探针那条 resolver 在链中靠前，一旦它的匹配条件写宽了
     * （例如只比 host 不比 path），就会把整个 security.demo.local 甚至更多 host
     * 一并吃掉，表现正是「所有资源都加载不出来」。
     */
    it('error_probe_resolver_does_not_swallow_other_hosts', 0, () => {
      assertSuccess('local-asset://assets.demo.local/static/styles.css');
      const notMine = resolve('local-asset://assets.demo.local/static/missing.css');
      // 探针不认领它，目录 resolver 也读不到 → 落到 RESOLUTION_ERROR，而不是被探针改写成别的类别。
      expect(notMine.kind).assertEqual('failure');
    });
  });
}
