import {
  ResourceResolver,
  ResolverResult,
  resolverHit,
  resolverSkip,
  AssetRequest,
  ResolveContext,
  createResourceDescriptor,
  bytesSource,
  ResourceType,
} from 'io.github.xesam.harmony.localasset.core';

/**
 * 场景 6（compatibility.md §13.6）里被链首 resolver 覆盖的那张横幅 **与**覆盖它的 resolver。
 *
 * 独立成纯模块（不含任何 ArkUI 类型），理由有两层：
 *
 * 1. 这是本场景中唯一有真值可断言的逻辑（`?mode=` → 不同字节），写进 @Component
 *    就再也测不到 —— 而 §13.6 的核心主张恰恰是「`?mode=` 驱动的动态解析必须体现
 *    DYNAMIC 资源类型」，「两个 mode 产出不同字节」正是 DYNAMIC 之所以为 DYNAMIC
 *    的可断言形式。
 * 2. resolver 的匹配条件（host + path）必须与共享 HTML 请求的 URL 一致。二者分居
 *    两处时没有任何东西把它们绑住 —— 改掉 resolver 里的字面量，全部单测照样绿，
 *    而页面会静默显示基础目录里那张 `Base Banner`，**不报错**。抽成常量后同源，
 *    再由 `OverrideBanner.test.ets` 端到端钉死。
 */

/** 与 shared/demo/pages/resolver-chain.html 里的 URL 逐字一致。 */
export const CHAIN_HOST = 'chain.demo.local';

/** 目录 resolver 的前缀；覆盖路径与基础路径同在其下（§13.6 要求同一命名空间）。 */
export const CHAIN_BASE_PREFIX = '/base';

/** 被链首 resolver 接管的那一条。基础目录里同名文件存在但永远不会被触达。 */
export const OVERRIDE_BANNER_PATH = '/base/banner.svg';

/**
 * ASCII 字符串 → 字节。
 *
 * **不用 `util.TextEncoder`**：`@ohos.util` 的编解码类在本仓的测试沙箱里返回空数据
 * （TextDecoder 实测如此，见 harmony/README.md「本地单元测试沙箱的系统能力限制」），拿它当依赖会让这段逻辑在测试里假通过。
 * 逐字符取 charCode 对 ASCII 恒等于 UTF-8，因此 `overrideBannerSvg` 的产出被刻意
 * 限制在 ASCII 之内 —— 若将来往 SVG 里塞中文，必须改用真正的 UTF-8 编码器，
 * 否则会静默产出损坏的字节。
 */
export function asciiBytes(text: string): Uint8Array {
  const bytes = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) {
    bytes[i] = text.charCodeAt(i) & 0xff;
  }
  return bytes;
}

/**
 * 按 `mode` 产出一张不同配色的横幅 SVG。内容随 query 变化，故承载它的 descriptor
 * 必须是 `ResourceType.DYNAMIC`（§13.6）。
 *
 * 缺省取 `dark`，与 Android `ResolverChainActivity.overrideBanner` 一致；
 * 共享页面首帧也是 `applyTheme("dark")`。
 *
 * 内容刻意标注 "Override"：验收时肉眼即可区分它与基础目录里那张同名 `banner.svg`
 * （后者永远不会被触达 —— 那正是"短路"的含义）。
 */
export function overrideBannerSvg(mode: string): string {
  const light = mode === 'light';
  const background = light ? '#fff7ed' : '#0f172a';
  const foreground = light ? '#fb923c' : '#38bdf8';
  const label = light ? 'Override (light)' : 'Override (dark)';
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 120">' +
    '<rect width="360" height="120" rx="24" fill="' + background + '"/>' +
    '<text x="180" y="70" text-anchor="middle" font-size="32" fill="' + foreground + '">' +
    label + '</text></svg>';
}

/** `overrideBannerSvg` 的字节形态，直接喂给 `bytesSource`。 */
export function overrideBannerBytes(mode: string): Uint8Array {
  return asciiBytes(overrideBannerSvg(mode));
}

/**
 * 链首的覆盖 resolver：只接管 `/base/banner.svg`，其余一律 Skip。
 *
 * `request.path` 不含 query（adapter 在解析时就把 `?` 之后的部分拆进了
 * `request.query`），所以这里用等值比较即可 —— 带不带 `?mode=` 都能匹配上。
 *
 * 匹配条件取自本文件顶部的常量，与共享 HTML 请求的 URL 同源 —— 见文件头注释。
 */
export class BannerOverrideResolver implements ResourceResolver {
  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    if (request.namespace !== CHAIN_HOST || request.path !== OVERRIDE_BANNER_PATH) {
      return resolverSkip();
    }
    const mode: string = request.query.get('mode') ?? 'dark';
    return resolverHit(createResourceDescriptor({
      id: 'override-banner-' + mode,
      namespace: request.namespace,
      // 内容随 query 变化 → DYNAMIC。标成 STATIC 会让主题切换被 Web 内核的缓存吃掉：
      // ResourceCachePolicy 按 type 决定缓存头，STATIC 走 max-age，DYNAMIC 走 no-store。
      type: ResourceType.DYNAMIC,
      source: bytesSource(overrideBannerBytes(mode)),
      mimeType: 'image/svg+xml',
      createdAtMillis: Date.now(),
    }));
  }
}
