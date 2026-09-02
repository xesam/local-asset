import { Policy } from '../api/Policy';
import { DEFAULT_HANDLE_HOST } from '../api/HandleRegistry';
import { AssetRequest } from '../model/AssetRequest';
import { ResolveContext } from '../model/ResolveContext';
import { ResourceDescriptor, ResourceScope, ResourceSource } from '../model/ResourceDescriptor';
import { ResourceErrorCategory } from '../error/ResourceErrorCategory';
import { ResourceException } from '../error/ResourceException';

const STAGE_PRE = 'policy_pre';
const STAGE_POST = 'policy_post';

export interface DefaultPolicyOptions {
  /** 允许的来源类型，取值为 ResourceSource 的 kind：'bytes' / 'filePath'。默认两者都允许。 */
  allowedSourceKinds?: string[];
  /** 允许的文件根。为空（默认）时所有 filePath 来源一律拒绝 —— 刻意的 fail-closed（design.md §5.5）。 */
  allowedFileRoots?: string[];
  /** 为空（默认）时不限制；非空时只放行列表内的 scheme。 */
  allowedSchemes?: string[];
  /** 为空（默认）时不限制；非空时只放行列表内的 namespace —— 但 handle host 永远豁免（见 handleHost）。 */
  allowedNamespaces?: string[];
  /** handle URI 铸造所在的 namespace，永远豁免于 allowedNamespaces。默认 `handles.localasset.local`。 */
  handleHost?: string;
  nowProvider?: () => number;
}

/**
 * 与 Kotlin `DefaultPolicy` 逐条核对过的两阶段门禁。**校验顺序是契约的一部分**：
 * 同时违反多条时，先触发的那条决定调用方看到的 category 与 message。
 *
 * - preCheck：scheme 非空 → scheme 白名单 → namespace 非空 → namespace 白名单 → 路径穿越
 * - postCheck：TTL → scope/namespace 匹配 → 来源类型白名单 → 文件根包含
 *
 * 三处易被"顺手简化"掉、但都是承重的细节：
 *
 * 1. **过期归 RESOLUTION_ERROR，不是 SECURITY_ERROR**。检查虽然写在 policy 里，
 *    但"资源过期"是解析结果的属性而非安全违规，与 Kotlin/iOS 及跨平台 fixture 一致。
 * 2. **TTL 判据是闭区间 `createdAtMillis + ttlMillis <= now`**（`<=` 不是 `<`），
 *    与 InMemoryResourceRegistry / InMemoryHandleRegistry 用的是同一个边界。
 * 3. **文件根比对前必须先规范化路径，再带分隔符比前缀**（见 normalizeAbsolutePath / isAllowedFilePath）。
 *
 * ## 关于 filePath 的规范化（与 Kotlin/iOS 的已知差异，务必读完再改）
 *
 * `descriptor.source.value` 由 resolver 产出，**从不经过 preCheck** —— preCheck 的 `..` 拦截
 * 只看 `request.path` 与 `request.identifier`。因此 postCheck 必须自己规范化，否则
 * `/data/app/cache/../../../etc/passwd` 会因为字符串前缀相同而被放行给 Loader。
 *
 * Kotlin 用 `File(path).canonicalFile.path`、iOS 用 `resolvingSymlinksInPath()`，两者都会
 * **访问文件系统**，因而连符号链接一起解析。OpenHarmony SDK 里**不存在**对应的 real-path API：
 * 已核查 `@ohos.file.fs` 全部导出函数（access/stat/lstat/symlink/open/read… 共 60 余个），
 * 无 realPath / readlink / readlinkSync；全 SDK 目录 grep `realpath|canonical` 也只命中
 * `@ohos.i18n`（无关）。`lstatSync` 能告诉你某一段"是不是"符号链接，但拿不到它的目标路径。
 *
 * "逐段 lstatSync 命中符号链接即拒"作为**默认开启**的缓解曾实现并实测否决——无 readlink 拿不到
 * 目标，只能无差别拒，会误伤落符号链接目录背后的合法文件（macOS `/etc`→`/private/etc`），
 * 破坏与 Kotlin/iOS 的跨端一致性。完整调查见 `docs/threat-model.md` §4.1，别再把无差别拒做成默认。
 *
 * 因此这里维持**纯词法规范化**（折叠 `.` 与 `..`，不碰文件系统），与历史行为一致：
 * - ✅ 已覆盖：`..` 穿越（无论逃出根还是折叠后仍在根内）、`.` 冗余段、根自带 `..`/尾斜杠、
 *   相对路径与逃出文件系统根的路径（一律 fail-closed 拒绝）。
 * - ⚠️ **未覆盖：符号链接逃逸**。根下若存在指向根外的符号链接，词法校验无法识别，靠调用方契约
 *   缓解（见 `docs/threat-model.md` §4.1）：仅把受控目录（App 私有缓存目录）声明为允许根，避免在
 *   允许根下放置用户可控的符号链接。SDK 若补上 readlink/realPath，应改为解析后重判（允许根下
 *   符号链接指向根内），而非检测即拒。
 *
 * policy 模块本身不引入 `@ohos.file.fs`：词法规范化不碰文件系统，从而 policy 能在 hvigor 沙箱里
 * 单测（core 的 loader/cache 模块另算，它们已直接依赖 fs）。
 */
export class DefaultPolicy implements Policy {
  private readonly allowedSourceKinds: string[];
  private readonly allowedFileRoots: string[];
  private readonly allowedSchemes: string[];
  private readonly allowedNamespaces: string[];
  private readonly handleHost: string;
  private readonly nowProvider: () => number;

  constructor(options?: DefaultPolicyOptions) {
    this.allowedSourceKinds = options?.allowedSourceKinds ?? ['bytes', 'filePath'];
    // 根在构造期就规范化一次，让比较的两侧永远处于同一形态
    // （Kotlin 在 allowedFileRootPaths 的 lazy 里做同样的事，iOS 在 init 里做）。
    // 无法规范化的根（相对路径、逃出文件系统根）直接丢弃 —— 留着它只会放行本不该放行的路径。
    const configuredRoots: string[] = options?.allowedFileRoots ?? [];
    const normalizedRoots: string[] = [];
    for (const root of configuredRoots) {
      const normalized = normalizeAbsolutePath(root);
      if (normalized !== null) {
        normalizedRoots.push(normalized);
      }
    }
    this.allowedFileRoots = normalizedRoots;
    this.allowedSchemes = options?.allowedSchemes ?? [];
    this.allowedNamespaces = options?.allowedNamespaces ?? [];
    this.handleHost = options?.handleHost ?? DEFAULT_HANDLE_HOST;
    this.nowProvider = options?.nowProvider ?? (() => Date.now());
  }

  preCheck(request: AssetRequest, context: ResolveContext): void {
    if (request.scheme.trim().length === 0) {
      throw new ResourceException(ResourceErrorCategory.SECURITY_ERROR, 'scheme must not be blank', STAGE_PRE);
    }
    if (this.allowedSchemes.length > 0 && !this.allowedSchemes.includes(request.scheme)) {
      throw new ResourceException(
        ResourceErrorCategory.SECURITY_ERROR,
        'scheme is not allowed: ' + request.scheme,
        STAGE_PRE,
      );
    }
    if (request.namespace.trim().length === 0) {
      throw new ResourceException(ResourceErrorCategory.SECURITY_ERROR, 'namespace must not be blank', STAGE_PRE);
    }
    if (this.allowedNamespaces.length > 0 && request.namespace !== this.handleHost && !this.allowedNamespaces.includes(request.namespace)) {
      throw new ResourceException(
        ResourceErrorCategory.SECURITY_ERROR,
        'namespace is not allowed: ' + request.namespace,
        STAGE_PRE,
      );
    }
    // 请求级路径穿越拦截（在任何 resolver 看到 path 之前的纵深防御）。
    // local-asset:// 路径里出现 .. 段永远不合法，会让目录型 resolver 逃出自己的根。
    // identifier 与 path 都要查：只查 path 的实现会漏掉把穿越藏进 identifier 的请求。
    if (hasTraversalSegment(request.path) || hasTraversalSegment(request.identifier)) {
      throw new ResourceException(ResourceErrorCategory.SECURITY_ERROR, 'path traversal is not allowed', STAGE_PRE);
    }
  }

  postCheck(request: AssetRequest, descriptor: ResourceDescriptor, context: ResolveContext): void {
    const ttlMillis = descriptor.ttlMillis;
    if (ttlMillis !== null && descriptor.createdAtMillis + ttlMillis <= this.nowProvider()) {
      throw new ResourceException(ResourceErrorCategory.RESOLUTION_ERROR, 'resource expired', STAGE_POST);
    }

    // design.md §5.3：scope 身份即 descriptor.namespace，须与上下文里**对应那一个**字段相等。
    // scope 为 null 时整条门禁跳过 —— Handle 路径（§5.4 能力令牌模型）正是靠这一点通行。
    const scope = descriptor.scope;
    if (scope !== null) {
      let expectedScopeId: string | null;
      let scopeLabel: string;
      if (scope === ResourceScope.ENGINE) {
        expectedScopeId = context.engineScope;
        scopeLabel = 'engine';
      } else if (scope === ResourceScope.PAGE) {
        expectedScopeId = context.pageScope;
        scopeLabel = 'page';
      } else {
        expectedScopeId = context.sessionScope;
        scopeLabel = 'session';
      }
      if (descriptor.namespace !== expectedScopeId) {
        throw new ResourceException(
          ResourceErrorCategory.SECURITY_ERROR,
          scopeLabel + ' scope mismatch',
          STAGE_POST,
        );
      }
    }

    const source: ResourceSource = descriptor.source;
    if (!this.allowedSourceKinds.includes(source.kind)) {
      throw new ResourceException(
        ResourceErrorCategory.SECURITY_ERROR,
        'source type is not allowed: ' + source.kind,
        STAGE_POST,
      );
    }

    if (source.kind === 'filePath' && !this.isAllowedFilePath(source.value)) {
      throw new ResourceException(
        ResourceErrorCategory.SECURITY_ERROR,
        'file source is outside allowed roots',
        STAGE_POST,
      );
    }
  }

  private isAllowedFilePath(path: string): boolean {
    // fail-closed：没声明任何允许的根 = 一条 filePath 都不放行（design.md §5.5）。
    if (this.allowedFileRoots.length === 0) {
      return false;
    }
    // 先规范化再比对。descriptor.source.value 从未经过 preCheck 的 `..` 拦截，
    // 少了这一步，/data/app/cache/../../../etc/passwd 会因前缀相同而被放行。
    // 规范化失败（相对路径、`..` 逃出文件系统根）一律拒绝 —— 对齐 Kotlin 的
    // `runCatching { ... }.getOrNull() ?: return false`，异常路径必须 fail-closed。
    const normalizedPath = normalizeAbsolutePath(path);
    if (normalizedPath === null) {
      return false;
    }
    for (const root of this.allowedFileRoots) {
      // 必须带上分隔符再比前缀：裸 startsWith('/data/app/cache') 会把兄弟目录
      // /data/app/cache-evil/x.png 也判成"根下"，那是一次真实的目录逃逸。
      if (normalizedPath === root || normalizedPath.startsWith(root + '/')) {
        return true;
      }
    }
    return false;
  }
}

/**
 * 纯词法规范化一个绝对路径：折叠 `.` 与 `..` 段、压掉重复分隔符、去掉尾分隔符。
 * 返回 null 表示"无法规范化"，调用方必须据此拒绝（fail-closed）。
 *
 * 不访问文件系统，因此**不解析符号链接** —— 见 DefaultPolicy 类注释里的残留风险说明。
 * 返回 null 的两种情形：
 *   1. 非绝对路径（不以 `/` 开头）—— 相对路径无从判断落在哪个根下；
 *   2. `..` 数量超过实际层级，逃出文件系统根（如 `/a/../..`）。
 * 根路径 `/` 规范化为 `''`，从而 `'' + '/'` = `/` 成为任何绝对路径的前缀，语义正确。
 *
 * 导出给 webview 的 `FileDirectoryResolver` 复用（同一算法，同一份实现）：
 * `resolveSource` 是 protected 扩展点，第三方子类可以绕过 `preCheck` 直接调用，
 * 所以那一层必须能独立完成同样的折叠校验，而不是依赖调用方已经跑过 `preCheck`。
 * "独立生效" 只要求这里的逻辑可以脱离 core 引擎单独调用，并不要求另抄一份代码。
 */
export function normalizeAbsolutePath(path: string): string | null {
  if (!path.startsWith('/')) {
    return null;
  }
  const stack: string[] = [];
  const segments: string[] = path.split('/');
  for (const segment of segments) {
    if (segment.length === 0 || segment === '.') {
      // 空段来自重复分隔符或尾分隔符；`.` 是无意义的自指段。两者都直接跳过。
      continue;
    }
    if (segment === '..') {
      if (stack.length === 0) {
        // 已在文件系统根，再上一层就逃出去了 —— 返回 null 拒绝，不静默钳到根。
        //
        // 这里刻意比参考实现更严。Java 的 canonicalFile 按 POSIX 语义把越过根的 `..`
        // **钳**在文件系统根上（实测：`/../data/app/cache/x.png` → `/data/app/cache/x.png`），
        // iOS 的 resolvingSymlinksInPath 同理。于是「前导 `..` 折叠后又落回某个允许根内」
        // 的路径，参考实现放行、本实现拒绝。
        //
        // 注意此分歧**不限于根 = '/'**：只要路径带前导 `..` 且钳回后仍在根内就会显形，
        // 任何根都可能遇到（见测试 `postCheck rejects a leading-.. path that Java would
        // clamp back into the root`）。方向始终是我们更保守 —— 只会多拒、绝不多放，
        // 因此不构成安全分歧，只是可用性上更严格。
        return null;
      }
      stack.pop();
      continue;
    }
    stack.push(segment);
  }
  return stack.length === 0 ? '' : '/' + stack.join('/');
}

function hasTraversalSegment(value: string | null): boolean {
  if (value === null || value.trim().length === 0) {
    return false;
  }
  const segments: string[] = value.split('/');
  for (const segment of segments) {
    if (segment === '..') {
      return true;
    }
  }
  return false;
}
