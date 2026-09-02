/**
 * 平台无关的 CORS 决策，保证三端对同一 (allow-list, request `Origin`) 下发**逐字节相同**的响应头。
 * 跨端契约由 `docs/compatibility-fixtures/cors-headers.json` 钉住。
 *
 * 与 Kotlin `CorsPolicy` / iOS `CorsPolicy` 逐行核对过。
 *
 * ## 为什么默认不发任何头
 *
 * `local-asset://` 响应对任何 `https://`（或 `file://`）页面都是跨源的，发
 * `Access-Control-Allow-Origin: *` 等于让该 WebView 里**每一个**源都能读这些字节——
 * 包括第三方 iframe 与注入脚本。这在 Handle 路径上尤其致命：其访问控制是 URL 路径里的
 * capability token（design.md §5.4），而 URL 路径会经 `document.referrer`、
 * 出站请求的 `Referer` 头、`performance.getEntriesByType('resource')` 泄漏；
 * 通配 CORS 把任一泄漏直接变成可读字节。
 *
 * `<img>`/`<link>`/`<script>`/`<video>` 根本不查 CORS，所以默认「不发头」仍能覆盖常见嵌入。
 * 只有 `fetch()`/`XMLHttpRequest` 需要头，而这些调用方知道自己的源——故用显式 allow-list。
 */
export const ALLOW_ANY_ORIGIN = '*';

const ALLOW_ORIGIN = 'Access-Control-Allow-Origin';
const ALLOW_METHODS = 'Access-Control-Allow-Methods';
const METHODS = 'GET, OPTIONS';

/**
 * 空响应头的共享单例，对齐 Kotlin `emptyMap()` / iOS `[:]`——默认（空 allow-list）路径是每请求
 * 都走的 hottest path（图片/脚本/样式表……），逐次 `new Map()` 徒增 GC 压力。调用方仅 `forEach`
 * 迭代返回值、从不 mutate，故共享一个空 Map 安全。
 */
const EMPTY_HEADERS: Map<string, string> = new Map<string, string>();

/**
 * - `allowedOrigins`：空 = 不发 CORS 头；含 `ALLOW_ANY_ORIGIN` = 通配；
 *   否则为精确匹配的源列表（`scheme://host[:port]`，无尾斜杠）。
 * - `requestOrigin`：请求的 `Origin` 头；缺省时（同源或非 CORS 请求）浏览器只对 CORS 与
 *   非 GET 请求发送该头，故 nil 表示无头。
 */
export function corsHeaders(
  allowedOrigins: Set<string>,
  requestOrigin: string | null,
): Map<string, string> {
  if (allowedOrigins.size === 0) {
    return EMPTY_HEADERS;
  }
  const headers = new Map<string, string>();
  if (allowedOrigins.has(ALLOW_ANY_ORIGIN)) {
    headers.set(ALLOW_ORIGIN, ALLOW_ANY_ORIGIN);
    headers.set(ALLOW_METHODS, METHODS);
    return headers;
  }
  if (requestOrigin !== null && allowedOrigins.has(requestOrigin)) {
    headers.set(ALLOW_ORIGIN, requestOrigin);
    headers.set(ALLOW_METHODS, METHODS);
    // 响应随请求 Origin 变化，故按 URL 单独 key 的缓存会把一个源的 allow 头发给另一个源。
    headers.set('Vary', 'Origin');
    return headers;
  }
  return headers;
}
