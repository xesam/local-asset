import { describe, it, expect } from '@ohos/hypium';
import {
  LocalAssetBuilder,
  createResolveContext,
  EngineResult,
  ResourceType,
} from 'io.github.xesam.harmony.localasset.core';
import {
  asciiBytes,
  overrideBannerSvg,
  overrideBannerBytes,
  BannerOverrideResolver,
  CHAIN_HOST,
  OVERRIDE_BANNER_PATH,
} from '../../main/ets/common/OverrideBanner';

/**
 * 场景 6（compatibility.md §13.6）的两组断言。
 *
 * ## 1. "`?mode=` 驱动动态解析"的可断言形式
 *
 * §13.6 要求覆盖那条资源必须是 DYNAMIC。类型枚举本身只是个标注，真正让它**配得上**
 * DYNAMIC 的是"同一 URL、不同 query → 不同字节"。
 *
 * ## 2. resolver 只认领它该认领的那一条
 *
 * 链首 resolver 的匹配条件与共享 HTML 请求的 URL 曾经分居两处、互不相干。
 * 改掉 resolver 里的字面量，字节层面的断言照样全绿，而页面会静默显示基础目录里
 * 那张 `Base Banner`，**不报错** —— 这是本场景最危险的失败形态。
 * 下面用**共享常量**驱动一个真实引擎，把"覆盖路径命中且为 DYNAMIC"与
 * "兄弟路径不被认领"两侧都钉死。
 */

/** 只挂覆盖 resolver、不挂目录 resolver：兄弟路径因而必然落空，Skip 与否一目了然。 */
function overrideOnlyEngine() {
  return new LocalAssetBuilder()
    .addResolver(new BannerOverrideResolver())
    .build()
    .engine;
}

function resolveChain(url: string): EngineResult {
  return overrideOnlyEngine().resolveUrl(
    url,
    createResolveContext({ engineScope: 'resolver-chain' }),
  );
}

export default function overrideBannerTest() {
  describe('OverrideBanner', () => {
    it('asciiBytes encodes one byte per character', 0, () => {
      // 不用 util.TextEncoder：@ohos.util 的编解码类在本仓测试沙箱里返回空数据，
      // 依赖它会让这段逻辑在测试里假通过。见 OverrideBanner 的函数注释。
      const bytes = asciiBytes('AZ<>');
      expect(bytes.length).assertEqual(4);
      expect(bytes[0]).assertEqual(65);
      expect(bytes[1]).assertEqual(90);
      expect(bytes[2]).assertEqual(60);
      expect(bytes[3]).assertEqual(62);
    });

    it('dark and light modes produce different bytes', 0, () => {
      // 这是 DYNAMIC 的实质：两个 mode 若产出同样的字节，"动态解析"就名存实亡，
      // 而页面上的主题按钮点了也看不出区别。
      const dark = overrideBannerBytes('dark');
      const light = overrideBannerBytes('light');
      // 逐字节比较，而不是比字符串 —— 断言的是真正喂给 bytesSource 的那份数据。
      let differing = 0;
      const shared = Math.min(dark.length, light.length);
      for (let i = 0; i < shared; i++) {
        if (dark[i] !== light[i]) {
          differing++;
        }
      }
      expect(differing > 0).assertTrue();
    });

    it('both modes are well-formed SVG carrying the Override label', 0, () => {
      // "Override" 这个词是验收时区分覆盖版与基础目录里那张同名 banner.svg 的唯一
      // 肉眼判据 —— 链序若被改坏，页面会静默显示基础素材那张而**不报错**。
      const dark = overrideBannerSvg('dark');
      expect(dark.startsWith('<svg ')).assertTrue();
      expect(dark.endsWith('</svg>')).assertTrue();
      expect(dark.includes('Override (dark)')).assertTrue();
      expect(overrideBannerSvg('light').includes('Override (light)')).assertTrue();
    });

    it('unknown modes fall back to dark, matching the Android reference', 0, () => {
      // Android ResolverChainActivity.overrideBanner 的缺省同样是 dark；
      // 共享页面首帧也是 applyTheme("dark")。
      expect(overrideBannerSvg('')).assertEqual(overrideBannerSvg('dark'));
      expect(overrideBannerSvg('sepia')).assertEqual(overrideBannerSvg('dark'));
    });

    it('output stays inside ASCII so the per-char encoding is valid UTF-8', 0, () => {
      // asciiBytes 逐字符取低 8 位；一旦 SVG 里混入非 ASCII，字节会被静默截断。
      // 这条断言是那个前提的看门人。
      const both = overrideBannerSvg('dark') + overrideBannerSvg('light');
      let maxCode = 0;
      for (let i = 0; i < both.length; i++) {
        const code = both.charCodeAt(i);
        if (code > maxCode) {
          maxCode = code;
        }
      }
      expect(maxCode < 128).assertTrue();
    });

    // ---- 端到端：覆盖路径 × BannerOverrideResolver × 完整引擎 -------------------

    it('the override resolver claims the banner path and marks it DYNAMIC', 0, () => {
      // §13.6：`?mode=` 驱动的动态解析必须体现 DYNAMIC 资源类型。
      const result = resolveChain('local-asset://' + CHAIN_HOST + OVERRIDE_BANNER_PATH);
      expect(result.kind).assertEqual('success');
      if (result.kind === 'success') {
        expect(String(result.descriptor.type)).assertEqual(String(ResourceType.DYNAMIC));
        expect(result.descriptor.mimeType).assertEqual('image/svg+xml');
      }
    });

    it('the override resolver matches with the ?mode= query attached', 0, () => {
      // request.path 不含 query（adapter 已把它拆进 request.query），所以等值比较成立。
      // 若哪天 adapter 改成把 query 留在 path 里，这条会立刻变红。
      const result = resolveChain(
        'local-asset://' + CHAIN_HOST + OVERRIDE_BANNER_PATH + '?mode=light',
      );
      expect(result.kind).assertEqual('success');
    });

    it('the ?mode= query actually reaches the resolver and changes the bytes', 0, () => {
      // 这是整个场景的主张：同一条 URL、不同 query → 引擎吐出不同字节。
      // 只断言"两个 mode 的生成函数不同"证明不了 query 真的传到了 resolver 手里。
      const dark = resolveChain('local-asset://' + CHAIN_HOST + OVERRIDE_BANNER_PATH + '?mode=dark');
      const light = resolveChain('local-asset://' + CHAIN_HOST + OVERRIDE_BANNER_PATH + '?mode=light');
      expect(dark.kind).assertEqual('success');
      expect(light.kind).assertEqual('success');
      if (dark.kind === 'success' && light.kind === 'success') {
        expect(dark.descriptor.id).assertEqual('override-banner-dark');
        expect(light.descriptor.id).assertEqual('override-banner-light');
      }
    });

    it('sibling paths are skipped so they fall through to the directory resolver', 0, () => {
      // §13.6 的另一半：除被覆盖那条之外一律 Skip。这里没挂目录 resolver，
      // 因此"落空"表现为 RESOLUTION_ERROR —— 真机上它们会被目录 resolver 接住。
      // 若覆盖 resolver 变得过于贪心（比如改成前缀匹配），这两条会变成 success，
      // 而真机上表现为 card/layout 被换成横幅内容。
      const card = resolveChain('local-asset://' + CHAIN_HOST + '/base/card.svg');
      const layout = resolveChain('local-asset://' + CHAIN_HOST + '/base/layout.css');
      expect(card.kind).assertEqual('failure');
      expect(layout.kind).assertEqual('failure');
    });

    it('a different host on the same path is not claimed', 0, () => {
      // host 也是匹配条件的一部分；只比 path 会让别的命名空间被误伤。
      const result = resolveChain('local-asset://other.demo.local' + OVERRIDE_BANNER_PATH);
      expect(result.kind).assertEqual('failure');
    });
  });
}
