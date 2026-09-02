import { describe, it, expect } from '@ohos/hypium';
import { localAssetCustomScheme, LOCAL_ASSET_SCHEME } from '../../main/ets/api/LocalAssetSchemeHandler';

/**
 * `customizeSchemes` 传入的配置。
 *
 * 这四个开关全都**只在真机上有表现**，任何一个漏掉都不会让编译或其余单测变红，
 * 却会让页面上一个资源都出不来 —— 而那种失败**不产生可见错误**，只能靠人工验收
 * 逐个排查。故在这里逐字钉死，让「谁把某个开关删了」当场变成一条失败用例。
 *
 * 本文件不碰 ArkWeb 运行时，只断言配置对象的字段值，因此可以在 hvigorw test 里跑。
 */
export default function customSchemeTest() {
  describe('LocalAssetCustomScheme', () => {
    it('scheme_name_is_cross_platform_contract', 0, () => {
      // 三端共用同一套 URL 形态，改这个字面量等于换掉整套契约。
      expect(LOCAL_ASSET_SCHEME).assertEqual('local-asset');
      expect(localAssetCustomScheme().schemeName).assertEqual('local-asset');
    });

    it('cors_and_fetch_are_enabled', 0, () => {
      // 关掉任一项，H5 的 fetch() / XMLHttpRequest 拿不到响应，
      // BridgeResponse 按 allowedOrigins 下发的 CORS 头也随此失去意义。
      const scheme = localAssetCustomScheme();
      expect(scheme.isSupportCORS).assertTrue();
      expect(scheme.isSupportFetch).assertTrue();
    });

    it('is_standard_so_host_and_path_split_correctly', 0, () => {
      // 非标准 scheme 的 URL 会被当作 opaque 处理，`local-asset://ns/id` 里的
      // host（namespace）与 path 就切不出来，而 core 的 SchemeAdapter 正按二者解析。
      expect(localAssetCustomScheme().isStandard).assertTrue();
    });

    it('security_flags_stay_unset_until_verified_on_device', 0, () => {
      // isSecure 试过，真机上把跳转变成 "too many redirects"，已回退。
      // 这三个开关只在真机上有表现，本仓没有任何自动化手段能验证它们 ——
      // 保持未设置，改动前先拿到真机结论。
      const scheme = localAssetCustomScheme();
      expect(scheme.isSecure === undefined).assertTrue();
      expect(scheme.isLocal === undefined).assertTrue();
      expect(scheme.isDisplayIsolated === undefined).assertTrue();
    });
  });
}
