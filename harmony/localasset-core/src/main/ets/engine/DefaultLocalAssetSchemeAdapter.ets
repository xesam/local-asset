import { SchemeAdapter } from '../api/SchemeAdapter';
import { AssetRequest, createAssetRequest } from '../model/AssetRequest';
import { ResourceErrorCategory } from '../error/ResourceErrorCategory';
import { ResourceException } from '../error/ResourceException';

const SCHEME = 'local-asset';
const SCHEME_SEPARATOR = '://';

/**
 * 手写解析而非依赖 @ohos.url：url.URL 的边界行为在不同 SDK 版本间有差异，
 * 而解析语义必须与 Android 的 java.net.URI、iOS 的 Foundation URLComponents 逐字段对齐。
 */
export class DefaultLocalAssetSchemeAdapter implements SchemeAdapter {
  canHandle(url: string): boolean {
    return url.startsWith(SCHEME + SCHEME_SEPARATOR);
  }

  parse(url: string): AssetRequest {
    if (!this.canHandle(url)) {
      throw new ResourceException(ResourceErrorCategory.PARSE_ERROR, 'unsupported scheme');
    }
    let rest = url.substring(SCHEME.length + SCHEME_SEPARATOR.length);

    let fragment: string | null = null;
    const hashIndex = rest.indexOf('#');
    if (hashIndex >= 0) {
      // Kotlin uri.fragment / iOS comps.fragment 都是解码后的值，且不做 '+'→空格 转换。
      fragment = decodeComponent(rest.substring(hashIndex + 1));
      rest = rest.substring(0, hashIndex);
    }

    let rawQuery = '';
    const queryIndex = rest.indexOf('?');
    if (queryIndex >= 0) {
      rawQuery = rest.substring(queryIndex + 1);
      rest = rest.substring(0, queryIndex);
    }

    const slashIndex = rest.indexOf('/');
    const namespace = slashIndex >= 0 ? rest.substring(0, slashIndex) : rest;
    if (namespace.length === 0) {
      throw new ResourceException(ResourceErrorCategory.PARSE_ERROR, 'missing namespace');
    }

    // 无斜杠时 Kotlin 的 uri.path 为空串，被 takeIf{isNotBlank} 拒绝 → missing path。
    // 而 'local-asset://image/' 的 path 为 '/'（非空白），Kotlin 与 iOS 均受理，故不能一并拒绝。
    const rawPath = slashIndex >= 0 ? rest.substring(slashIndex) : '';
    if (rawPath.length === 0) {
      throw new ResourceException(ResourceErrorCategory.PARSE_ERROR, 'missing path');
    }
    const prefixedPath = rawPath.startsWith('/') ? rawPath : '/' + rawPath;

    // 与 Kotlin uri.getPath() / iOS comps.path 一致：整条 path 先解码，再按 '/' 取末段。
    // 实测两个参考实现里 %2F 解码成真斜杠后 *确实* 会产生新的分段边界
    // （'/a%2Fb' → path '/a/b' → identifier 'b'），所以不能先分段后解码。
    const path = decodeComponent(prefixedPath);

    const segments = path.split('/');
    const lastSegment = segments[segments.length - 1];
    const identifier = lastSegment.length > 0 ? lastSegment : null;

    return createAssetRequest({
      scheme: SCHEME,
      namespace: namespace,
      identifier: identifier,
      path: path,
      query: parseQuery(rawQuery),
      fragment: fragment,
    });
  }
}

function parseQuery(rawQuery: string): Map<string, string> {
  const result = new Map<string, string>();
  if (rawQuery.length === 0) {
    return result;
  }
  const parts = rawQuery.split('&');
  for (const part of parts) {
    if (part.length === 0) {
      continue;
    }
    const equalsIndex = part.indexOf('=');
    const rawKey = equalsIndex >= 0 ? part.substring(0, equalsIndex) : part;
    const rawValue = equalsIndex >= 0 ? part.substring(equalsIndex + 1) : '';
    result.set(decodeQueryComponent(rawKey), decodeQueryComponent(rawValue));
  }
  return result;
}

/**
 * query 用 HTML form 语义（'+' 视作空格），对齐 Kotlin 的 URLDecoder.decode。
 * path/fragment 不能走这条：Kotlin 的 uri.path / uri.fragment 保留字面 '+'。
 */
function decodeQueryComponent(value: string): string {
  return decodeComponent(value.replace(/\+/g, ' '));
}

/**
 * 畸形转义（如 '%ZZ'、结尾孤立的 '%'）会让 decodeURIComponent 抛 URIError；
 * Kotlin 侧 java.net.URI 构造同样直接抛 URISyntaxException 并被归一为 'invalid url'。
 * 收敛成 PARSE_ERROR 以保持一致，也让 'invalid url' 这条消息真正可达。
 *
 * ---
 * 【勿"修正"】合法十六进制但非法 UTF-8 的转义（如 '%FF'）是三端无法消除的分歧。
 * 对 'local-asset://image/%FF' 三端实测（JVM + Swift + ArkTS 沙箱内实跑）：
 *   Kotlin  getPath() == "/" + U+FFFD（替换字符，isBlank 为 false）→ 受理，不报错
 *   iOS     URLComponents.path == ""（空串）                        → 'missing path'
 *   ArkTS   decodeURIComponent 抛 URIError                          → 'invalid url'
 * Android 与 iOS 本身就互不一致，harmony 不可能同时对齐两者，**因此不要把这里改成
 * 向任何一端靠拢** —— 那只会从另一端叉开。三端 category 均为 PARSE_ERROR，仅 message 不同，
 * 且 docs/compatibility-fixtures 不断言 message，故实际契约未被破坏。
 *
 * 同理，URL 同时有两处畸形时 message 取决于校验顺序：'local-asset://image?q=%ZZ'
 * 在 harmony 得 'missing path'（namespace/path 校验先于 query 解码），Kotlin 得 'invalid url'
 * （URI 构造阶段就整体失败）。实测 iOS 此例也是 'missing path'，与 harmony 一致。
 * 同为 PARSE_ERROR，且仅在"一个 URL 同时坏两处"时出现，不值得为它调整校验顺序。
 */
function decodeComponent(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (error) {
    throw new ResourceException(ResourceErrorCategory.PARSE_ERROR, 'invalid url');
  }
}
