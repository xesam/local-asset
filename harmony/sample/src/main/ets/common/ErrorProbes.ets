import {
  ResourceResolver,
  ResolverResult,
  resolverHit,
  resolverSkip,
  AssetRequest,
  ResolveContext,
  createResourceDescriptor,
  bytesSource,
  filePathSource,
  ResourceSource,
  ResourceType,
  ResourceScope,
} from 'io.github.xesam.harmony.localasset.core';

/**
 * 场景 5（compatibility.md §13.5）的四条探针 URL **与**产出前两条所需 descriptor 的 resolver。
 *
 * ## 为什么 URL 与 resolver 必须待在同一个文件里
 *
 * 二者曾经分居两处：URL 常量在这里，`ErrorProbeResolver` 在当时的
 * 错误分类场景页里硬编码同样的 host 与 path。**没有任何东西把它们绑住** ——
 * 改掉 resolver 里的 namespace 字面量，全部单测照样绿，而页面上 LOAD 那一行会静默退化成
 * `RESOLUTION_ERROR @ resolve`（谁都不认领了）。那正是 §13.5 存在的意义所要防的
 * 「类别错得悄无声息」，也正是本场景注释里点名的头号风险。
 *
 * 现在 host / path 被抽成下面的常量，URL 与 resolver 的匹配条件**同源**：
 * 改一处两边一起改，改不出分歧。`ErrorProbes.test.ets` 另有一条端到端断言把
 * 「`LOAD_PROBE_URL` 经完整引擎必须得到 LOAD_ERROR @ load」钉死。
 *
 * ## 独立成纯模块（不含任何 ArkUI 类型）
 *
 * 这样它才能被 `src/test` 直接构造与调用 —— hvigor 的 test 目标编译不进 UI 组件，
 * 落在 @Component 文件里的类只能被编译，不能被验证。
 *
 * `kind` 的四个取值由共享页面 shared/demo/pages/error-categories.html 的
 * `button[data-kind]` 决定（parse / resolution / load / security），改名会让
 * 同一份 HTML 在本端点了没反应。
 */

/** LOAD 探针的 host + path。URL 常量与 resolver 的匹配条件都由它派生 —— 见文件头注释。 */
export const LOAD_PROBE_HOST = 'errorcat.demo.local';
export const LOAD_PROBE_PATH = '/load-boom';

/** SECURITY 探针的 host + path。与 §13.4 复用同一条 mismatch URL。 */
export const SECURITY_PROBE_HOST = 'security.demo.local';
export const SECURITY_PROBE_PATH = '/engine-mismatch';

/** 该 descriptor 的 namespace，刻意 != engineScope（`demo-engine`），故必然在 postCheck 被拒。 */
export const SECURITY_PROBE_NAMESPACE = 'other-engine';

/** PARSE_ERROR @ adapter_parse —— 无 host，adapter 直接拒绝。 */
export const PARSE_PROBE_URL = 'local-asset://';

/** RESOLUTION_ERROR @ resolve —— 链上没有任何 resolver 认领它。 */
export const RESOLUTION_PROBE_URL = 'local-asset://nobody.demo.local/x';

/**
 * LOAD_ERROR @ load —— descriptor 的 FilePath 落在**允许的根之下**（因此过得了
 * postCheck 的文件根包含检查），但那个文件在磁盘上并不存在，于是被 loader 拒绝。
 *
 * 这条最容易做错：若忘记 `addAllowedFileRoot`，DefaultPolicy 对 filePath 是
 * fail-closed 的，失败会提前变成 SECURITY_ERROR @ policy_post —— 页面上照样红一片，
 * 但证明的是**另一件事**，而 §13.5 这一格要的恰恰是 loader 阶段的失败。
 */
export const LOAD_PROBE_URL = 'local-asset://' + LOAD_PROBE_HOST + LOAD_PROBE_PATH;

/** SECURITY_ERROR @ policy_post —— ENGINE scope 下 namespace != engineScope。 */
export const SECURITY_PROBE_URL = 'local-asset://' + SECURITY_PROBE_HOST + SECURITY_PROBE_PATH;

/**
 * `kind` → 探针 URL。未知 kind 返回 null，调用方据此静默忽略
 * （对齐 Android `ErrorCategoriesActivity.trigger` 的 `else -> return`）。
 */
export function errorProbeUrl(kind: string): string | null {
  if (kind === 'parse') {
    return PARSE_PROBE_URL;
  }
  if (kind === 'resolution') {
    return RESOLUTION_PROBE_URL;
  }
  if (kind === 'load') {
    return LOAD_PROBE_URL;
  }
  if (kind === 'security') {
    return SECURITY_PROBE_URL;
  }
  return null;
}

/**
 * 产出那两条「需要先命中、再在后续阶段失败」的 descriptor。
 * 其余路径一律 Skip —— RESOLUTION 那条探针正是靠"谁都不认领"落到
 * `resource not found`（RESOLUTION_ERROR @ resolve）。
 *
 * 匹配条件取自本文件顶部的常量，与 `LOAD_PROBE_URL` / `SECURITY_PROBE_URL` 同源。
 *
 * ## 为什么不用 `LocalAsset.register()`
 *
 * `RegistryResolver` 按 `request.identifier` 反查，identifier 是 URL 的**末段**，
 * 两条探针的末段（`load-boom` / `engine-mismatch`）确实对得上。但 registry 是
 * **全局按 id 索引、不区分 namespace** 的 —— 那样注册出来的资源在**任何** host 下
 * 都能查到，而 SECURITY 那条探针的唯一变量正是 namespace，说服力被削弱。
 * 显式按 `namespace + path` 配对与 Android `ErrorCategoriesActivity` 一致。
 */
export class ErrorProbeResolver implements ResourceResolver {
  private readonly missingFilePath: string;

  /**
   * @param missingFilePath 必须落在引擎的某个 allowed file root 之下，且该文件
   *   **不存在**。两个条件缺一不可：不在根下 → 提前栽在 postCheck（SECURITY_ERROR）；
   *   文件存在 → 整条探针会成功，表格里显示 `OK` 哨兵。
   */
  constructor(missingFilePath: string) {
    this.missingFilePath = missingFilePath;
  }

  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    if (request.namespace === LOAD_PROBE_HOST && request.path === LOAD_PROBE_PATH) {
      // 允许根之下、但磁盘上不存在 → 过 postCheck，栽在 loader。
      return resolverHit(descriptor(
        'load-boom',
        LOAD_PROBE_HOST,
        null,
        filePathSource(this.missingFilePath),
      ));
    }
    if (request.namespace === SECURITY_PROBE_HOST && request.path === SECURITY_PROBE_PATH) {
      // ENGINE scope + namespace(other-engine) !== engineScope(demo-engine) → postCheck 拒。
      return resolverHit(descriptor(
        'engine-mismatch',
        SECURITY_PROBE_NAMESPACE,
        ResourceScope.ENGINE,
        bytesSource(new Uint8Array(0)),
      ));
    }
    return resolverSkip();
  }
}

function descriptor(
  id: string,
  namespace: string,
  scope: ResourceScope | null,
  source: ResourceSource,
) {
  return createResourceDescriptor({
    id: id,
    namespace: namespace,
    type: ResourceType.DYNAMIC,
    source: source,
    createdAtMillis: Date.now(),
    scope: scope,
  });
}
