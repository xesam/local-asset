import { AssetRequest } from '../model/AssetRequest';
import { ResourceHandle, ResourceHandleRecord } from '../model/ResourceHandle';

/**
 * 保留的缓存击穿查询参数。
 *
 * 存在理由：WebView 对同一条 URL 的二次请求可能直接吃缓存，根本不进 scheme handler。
 * 调用方给 handle URI 追加 `?_la_cb=<变化值>` 即可打穿缓存，而这个参数**不参与 handle
 * 身份识别** —— 反查前必须剔除，否则加了它就再也查不到原条目。
 * 除它以外的 query key 仍是身份的一部分（跨平台契约，见 Kotlin HandleRegistry.CACHE_BUST_PARAM）。
 */
export const CACHE_BUST_PARAM = '_la_cb';

/**
 * 默认的 handle URI host（namespace）：`handles.localasset.local`。
 * Handle 路径靠能力令牌授权、不靠 namespace（design.md §5.4），故 `DefaultPolicy` 把这个
 * namespace 从 namespace 白名单里**豁免**——否则声明一个白名单就会把所有 handle URI 静默拒掉。
 * 自定义 `HandleRegistry` 若用别的 host 铸造 URI，须把该 host 传给 `DefaultPolicy.handleHost`。
 */
export const DEFAULT_HANDLE_HOST = 'handles.localasset.local';

/**
 * 从 AssetRequest 还原出注册时那条 URI。
 *
 * 契约：还原结果必须与 `register()` 返回的字符串**逐字节一致** —— scheme、host(namespace)、
 * path、query 编码与顺序、fragment 全部一致。不一致时 lookup 只会静默 miss
 * （`resolveFromRequest` → null → resolver Skip），不会报错，所以这里出偏差极难发现。
 *
 * query 的拼接顺序取 `request.query` 的迭代序（ArkTS Map 保持插入序），与 Kotlin
 * `identityQuery.entries.joinToString("&")` 对齐。自定义 HandleRegistry 若以别的编码/顺序
 * 铸造 URI，必须自行覆写反查逻辑以复现它注册的那个字符串。
 *
 * 注意：`register()` 铸造的 URI 从不带 query，所以 handle 的身份实际上**就是 path**；
 * 任何非 `_la_cb` 的 query 或 fragment 出现都会让还原串与注册串不等 → 必然 miss。
 * 这是刻意的：能力凭证不允许被附加参数悄悄改写语义。
 */
export function reconstructUriFromRequest(request: AssetRequest): string {
  const path: string = request.path ?? ('/' + (request.identifier ?? ''));
  let uri = request.scheme + '://' + request.namespace + path;
  const parts: string[] = [];
  request.query.forEach((value: string, key: string) => {
    if (key !== CACHE_BUST_PARAM) {
      parts.push(key + '=' + value);
    }
  });
  if (parts.length > 0) {
    uri += '?' + parts.join('&');
  }
  const fragment = request.fragment;
  if (fragment !== null) {
    uri += '#' + fragment;
  }
  return uri;
}

/**
 * Handle 路径的注册表（design.md §5.4）：与 Registry 路径的 namespace/scope 模型不同，
 * 这里是**能力令牌（capability）模型** —— `register()` 返回的不透明 URI 本身就是凭证，
 * 持有即授权；安全性由 token 不可猜测 + 可吊销（remove）+ 会过期（TTL）三者保证。
 *
 * 因此 `resolve` **抛错**而不是像 `ResourceRegistry.lookup` 那样返回 hit/missing/expired 三态：
 * 拿着一条无效凭证来换资源属于异常，而不是 resolver 探测「这归不归我管」的日常分支。
 * 需要日常分支语义的调用方走 `resolveFromRequest`（miss 返回 null）。
 */
export interface HandleRegistry {
  register(handle: ResourceHandle): string;

  /** 未知或已过期时抛 ResourceException(RESOLUTION_ERROR)。 */
  resolve(resourceUri: string): ResourceHandleRecord;

  /** 反查失败（含过期）返回 null，不抛错。 */
  resolveFromRequest(request: AssetRequest): ResourceHandleRecord | null;

  /** 显式吊销；未知 URI 为 no-op。 */
  remove(resourceUri: string): void;

  cleanup(nowMillis?: number): void;
}
