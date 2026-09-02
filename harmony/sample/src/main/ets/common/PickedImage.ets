/**
 * 场景 8（compatibility.md §13.8）里那几段从选图 URI 派生文件名 / MIME / 落地路径的逻辑。
 *
 * 独立成纯函数文件，理由与 `BridgePayloads` / `ErrorProbes` / `OverrideBanner` 相同：
 * 这是本场景中唯一有真值可断言的部分（字符串派生），而 `chooseImage` /
 * `submitImage` 的其余步骤都是 IO 与桥调用，在本仓无法自动化验证。
 */

/** 落地文件名里允许保留的字符之外的一律替换成 `_`。与 InMemoryHandleRegistry 的净化规则同形。 */
const UNSAFE_FILE_NAME = /[^A-Za-z0-9._-]/g;

/**
 * 从选图返回的 URI 里取文件名。
 *
 * photoAccessHelper 给出的形如
 * `file://media/Photo/12/IMG_1712345678_001/IMG_20240101_120000.jpg`，末段即文件名。
 * URI 带 query 或 fragment 时先剔除 —— 否则文件名里会混进 `?xxx`，
 * 既污染 handle URI 的末段，也污染落地文件名。
 *
 * 取不到末段（URI 以 `/` 结尾、或整体为空）时回落到 `picked-image`，
 * 而不是产出一个空文件名 —— 空名会让 handle URI 变成 `.../<token>/`，
 * 反查时末段为空，是一条走不通的路。
 */
export function fileNameFromPickerUri(uri: string): string {
  let path = uri;
  const hashIndex = path.indexOf('#');
  if (hashIndex >= 0) {
    path = path.substring(0, hashIndex);
  }
  const queryIndex = path.indexOf('?');
  if (queryIndex >= 0) {
    path = path.substring(0, queryIndex);
  }
  const slashIndex = path.lastIndexOf('/');
  const name = slashIndex >= 0 ? path.substring(slashIndex + 1) : path;
  return name.length > 0 ? name : 'picked-image';
}

/**
 * 按扩展名猜图片 MIME。
 *
 * **不复用 webview 模块的 `guessMimeType`**：那张表返回 `string | null`，
 * 而 `ResourceHandle.mimeType` 是非空 `string`，且这里的语境已经限定为"用户从相册
 * 选出来的图片"—— 没有扩展名时回落到 `image/jpeg` 比回落到 `application/octet-stream`
 * 更贴近事实（相册里绝大多数是 JPEG），也让 `<img>` 预览不至于因 Content-Type
 * 被当成下载。这是本场景的局部约定，不是库的推断策略。
 */
export function guessImageMime(fileName: string): string {
  const lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lower.endsWith('.gif')) {
    return 'image/gif';
  }
  if (lower.endsWith('.bmp')) {
    return 'image/bmp';
  }
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
    return 'image/heic';
  }
  return 'image/jpeg';
}

/**
 * 提交阶段的落地文件名：`submitted-<净化后的原名>`。
 *
 * 净化是**必须**的，不是美观问题：`record.fileName` 保留的是调用方给的原名
 * （InMemoryHandleRegistry 只净化 URI 段，不动 record），其中可能含 `/`，
 * 直接拼进沙箱路径就会写到别的目录去，或者因中间目录不存在而 open 失败。
 */
export function submittedFileName(fileName: string): string {
  const safe = fileName.replace(UNSAFE_FILE_NAME, '_');
  return 'submitted-' + (safe.length > 0 ? safe : 'picked-image');
}
