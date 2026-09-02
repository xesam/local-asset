import {
  ResourceResolver,
  ResolverResult,
  resolverHit,
  resolverSkip,
  AssetRequest,
  ResolveContext,
  ResourceSource,
  ResourceType,
  createResourceDescriptor,
} from 'io.github.xesam.harmony.localasset.core';

/**
 * 扩展名 → MIME 的静态表。
 *
 * **为什么是手写表**：Android 侧走 `MimeTypeMap.getSingleton()`，iOS 侧走
 * `UTType(filenameExtension:)?.preferredMIMEType`，两端都由系统提供。OpenHarmony SDK
 * 没有等价能力 —— `@ohos.data.uniformTypeDescriptor` 只做 UTD 类型 ID 与 MIME 的互查
 * (`getUniformDataTypeByMIMEType` / `getUniformDataTypeByFilenameExtension`)，
 * 无「扩展名 → MIME」这一步；`@ohos.web.webview` 的 `getMimeType()` 是读请求头，不是查表。
 * 故本表按 spec 与 sample 实际用到的 Web 资源类型手写，条目取值与 IANA 注册名一致。
 *
 * ## 与 compatibility.md §8.2 的偏离（"若允许推断，则双端推断策略一致"）
 *
 * 本表是**闭表**：由系统数据库改为固定 20 条，与 Android/iOS 的推断策略不再逐位一致。
 * 两类偏离都是已知且刻意的，**不要为了追平而扩表** —— 手写表追不动两端各自演进的
 * 系统数据库，闭合且写明白，好过敞开且悄悄漂移。
 *
 * ### 1. 取值分歧（同一扩展名，三端 MIME 不同）
 *
 * | ext    | harmony              | Android                    | iOS                          |
 * |--------|----------------------|----------------------------|------------------------------|
 * | `xml`  | `application/xml`    | `text/xml`                 | `text/xml`                   |
 * | `js`   | `text/javascript`    | `application/javascript`   | `text/javascript`            |
 * | `ico`  | `image/x-icon`       | `image/x-icon`             | `image/vnd.microsoft.icon`   |
 *
 * 三者都是同一媒体类型的合法别名，浏览器一视同仁，无功能后果。
 * `js`/`mjs` 取 `text/javascript`：RFC 9239 起 `application/javascript` 已 obsolete。
 *
 * ### 2. 闭表缺口（表外扩展名 → null → 响应层回落 `application/octet-stream`）
 *
 * 而 Android/iOS 会给出真实类型。**已知功能后果：`wasm`** ——
 * `WebAssembly.instantiateStreaming()` 强制要求 `application/wasm`，收到
 * octet-stream 会直接 reject，模块加载失败（不是降级，是报错）。
 * `mp3` / `wav` / `zip` / `avif` 是同一形态，但只影响 Content-Type 标注，不阻断加载。
 *
 * 需要这些类型的调用方，应当自己实现 `ResourceResolver` 并显式给出 `mimeType`，
 * 而不是依赖本表推断。
 */
const MIME_BY_EXTENSION: Map<string, string> = buildMimeTable();

function buildMimeTable(): Map<string, string> {
  // 不用 `new Map([[k, v], ...])` 的数组字面量形式：ArkTS 对嵌套数组字面量的类型推断
  // 会落到 any 上（arkts-no-any-unknown），逐条 set 是本仓已验证可编译的写法。
  const table = new Map<string, string>();
  table.set('css', 'text/css');
  table.set('js', 'text/javascript');
  table.set('mjs', 'text/javascript');
  table.set('html', 'text/html');
  table.set('htm', 'text/html');
  table.set('json', 'application/json');
  table.set('svg', 'image/svg+xml');
  table.set('png', 'image/png');
  table.set('jpg', 'image/jpeg');
  table.set('jpeg', 'image/jpeg');
  table.set('gif', 'image/gif');
  table.set('webp', 'image/webp');
  table.set('ico', 'image/x-icon');
  table.set('txt', 'text/plain');
  table.set('xml', 'application/xml');
  table.set('woff', 'font/woff');
  table.set('woff2', 'font/woff2');
  table.set('ttf', 'font/ttf');
  table.set('mp4', 'video/mp4');
  table.set('pdf', 'application/pdf');
  return table;
}

/** 按扩展名猜 MIME；无扩展名、末位裸点、或表中无此项时返回 null。 */
export function guessMimeType(path: string): string | null {
  const dotIndex = path.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex === path.length - 1) {
    return null;
  }
  const extension = path.substring(dotIndex + 1).toLowerCase();
  const mimeType = MIME_BY_EXTENSION.get(extension);
  return mimeType === undefined ? null : mimeType;
}

/** 规范化路径前缀：补前导 `/`、去尾部 `/`。`'/'` 规范化为 `''`（表示"整个 host 之下"）。 */
export function normalizePathPrefix(value: string): string {
  const withLeadingSlash = value.startsWith('/') ? value : '/' + value;
  return withLeadingSlash.endsWith('/')
    ? withLeadingSlash.substring(0, withLeadingSlash.length - 1)
    : withLeadingSlash;
}

/**
 * 前缀匹配**必须带分隔符**：裸 `path.startsWith(prefix)` 会把 `/static-evil/a.css`
 * 判成 `/static` 之下，于是一个仅仅前缀同形的兄弟目录就能被映射进来。
 * 这与 core `DefaultPolicy.isAllowedFilePath` 的文件根比对是同一类缺陷、同一个修法。
 */
export function matchesPrefix(path: string, prefix: string): boolean {
  return path === prefix || path.startsWith(prefix + '/');
}

/**
 * 剥掉前缀，得到相对路径。返回 null 表示"不可用"，调用方据此 Skip：
 *  - 剥完为空（请求打的正是前缀目录本身，没有具体资源）；
 *  - 含 `..` 段（路径穿越）。
 *
 * 判据是**整段相等**而不是 `includes('..')`：`..hidden.css` 与 `a..b.css` 是合法文件名，
 * 子串判定会连它们一起拒掉。
 *
 * 注：core 的 `DefaultPolicy.preCheck` 已在请求级拦过一次 `..`，这里是纵深防御 ——
 * resolver 可以脱离引擎被单独构造和调用（测试、第三方直接复用 BaseDirectoryResolver），
 * 不能把安全性外包给上游那一道门。
 */
export function extractRelativePath(path: string, normalizedPrefix: string): string | null {
  let relative = path.substring(normalizedPrefix.length);
  while (relative.startsWith('/')) {
    relative = relative.substring(1);
  }
  if (relative.length === 0) {
    return null;
  }
  const segments: string[] = relative.split('/');
  for (const segment of segments) {
    if (segment === '..') {
      return null;
    }
  }
  return relative;
}

/**
 * `host + pathPrefix -> relativePath` 的共享路由骨架，对应 Android 的同名抽象类。
 * 子类只需把一个**已校验、无穿越风险**的 relativePath 变成 ResourceSource。
 *
 * 产出的 descriptor 恒为 `STATIC` / `ttlMillis: null` / `scope: null` —— 目录型资源是
 * 随包分发的静态内容，没有生命周期也不绑定调用方身份。真正的门禁在 postCheck：
 * FilePath 来源还要过 `DefaultPolicy` 的文件根白名单（默认 fail-closed）。
 *
 * 公开（而非 internal）：两个子类都由使用方在模块外直接构造，第三方也可继承它接自己的存储。
 */
export abstract class BaseDirectoryResolver implements ResourceResolver {
  private readonly host: string;
  private readonly normalizedPathPrefix: string;

  constructor(host: string, pathPrefix: string) {
    this.host = host;
    this.normalizedPathPrefix = normalizePathPrefix(pathPrefix);
  }

  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    if (request.namespace !== this.host) {
      return resolverSkip();
    }
    const path = request.path;
    if (path === null || !matchesPrefix(path, this.normalizedPathPrefix)) {
      return resolverSkip();
    }
    const relativePath = extractRelativePath(path, this.normalizedPathPrefix);
    if (relativePath === null) {
      return resolverSkip();
    }
    const source = this.resolveSource(relativePath);
    if (source === null) {
      return resolverSkip();
    }
    return resolverHit(createResourceDescriptor({
      id: this.host + ':' + path,
      namespace: this.host,
      type: ResourceType.STATIC,
      source: source,
      mimeType: guessMimeType(relativePath),
      createdAtMillis: Date.now(),
      ttlMillis: null,
      scope: null,
    }));
  }

  /** 返回该 relativePath 对应的来源；无法加载时返回 null（转成 Skip）。 */
  protected abstract resolveSource(relativePath: string): ResourceSource | null;
}
