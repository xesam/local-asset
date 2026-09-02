import { EngineResult, ResourceException, ResourceErrorCategory } from 'io.github.xesam.harmony.localasset.core';

/**
 * 演示页与 H5 之间那几条回调的 payload 构造。
 *
 * 独立成纯函数文件的理由：这里是四个演示场景中**唯一有真值可断言**的逻辑
 * （JSON 转义、category/stage 的提取与缺省），而它一旦写进 @Component 的方法体
 * 就再也测不到 —— 本仓没有 ArkUI 测试手段。放这里才能被 `src/test` 覆盖。
 *
 * 共享 HTML（shared/demo/pages/*.html）约定的回调形状，三端一致：
 *   window.LocalAssetSampleNative.onProbe({ ok, category, stage, message })
 * `ok: true` 时其余字段缺省。字段名是跨端契约，改名会让同一份 HTML 在别处失效。
 */

/**
 * 把字符串转成一个可直接拼进 JS 源码的字面量。
 *
 * 必须自己写：Android 有 `JSONObject.quote`，ArkTS 只有 `JSON.stringify`。
 * `JSON.stringify('a')` 恰好产出 `"a"`，正是我们要的形态，但它对
 * 行分隔符 U+2028 / U+2029 **不转义** —— 这两个字符在 JSON 里合法，在 JS 源码里
 * 却是换行符，直接拼进 runJavaScript 会把语句拦腰截断（经典的 JSON-in-JS 陷阱）。
 * 资源 URI 里出现它们的概率极低，但这条转义是一次性成本，没有理由省。
 */
export function jsString(value: string): string {
  return JSON.stringify(value)
    .replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029');
}

/** `{"ok":true}` —— 探测成功。 */
export function probeOkPayload(): string {
  return '{"ok":true}';
}

/**
 * 探测失败的 payload。stage 为 null 时输出 JSON null，H5 侧用 `?? "-"` 兜底
 * （见 shared/demo/pages/handle-lifecycle.html）。
 */
export function probeFailurePayload(
  category: string,
  stage: string | null,
  message: string,
): string {
  const stageJson = stage === null ? 'null' : jsString(stage);
  return '{"ok":false,"category":' + jsString(category) +
    ',"stage":' + stageJson +
    ',"message":' + jsString(message) + '}';
}

/**
 * `engine.resolveUrl` 的结果 → 探测 payload。
 *
 * 直接取 `EngineFailure` 自带的 category / stage / reason，不做任何再分类 ——
 * compatibility.md §13.5 要求「复用正式 EngineResult 失败态的 category + stage，
 * 而非 sample 自造分类」。
 */
export function engineResultPayload(result: EngineResult): string {
  if (result.kind === 'success') {
    return probeOkPayload();
  }
  return probeFailurePayload(String(result.category), result.stage, result.reason);
}

/**
 * 从 `resolveHandle` 抛出的异常里取 category / stage / message。
 *
 * `InMemoryHandleRegistry` 抛的 ResourceException **不带 stage**（构造时省略，
 * 默认 null）—— 它是被直接调用的注册表，不在引擎流水线里，没有阶段可言。
 * 但 compatibility.md §13.3 要求这条失败在 H5 侧表现为 `RESOLUTION_ERROR` @ `resolve`：
 * 那正是同一条 URI 走 WebView 请求时引擎会给出的阶段。所以在这里补上 `resolve`
 * 作为缺省，使原生探测入口与图片加载路径报出同一个 (category, stage) 二元组。
 *
 * 非 ResourceException（组件内部 bug）归到 RESOLUTION_ERROR：探测入口的语义是
 * 「这条凭证还能不能换到资源」，任何异常的答案都是不能。
 */
export function handleExceptionPayload(error: Object): string {
  if (error instanceof ResourceException) {
    return probeFailurePayload(String(error.category), error.stage ?? 'resolve', error.message);
  }
  const message = error instanceof Error ? error.message : String(error);
  return probeFailurePayload(String(ResourceErrorCategory.RESOLUTION_ERROR), 'resolve', message);
}

/**
 * `onRegister` 的 payload：`{"uri": "<capability uri>"}`。
 * 字段名 `uri` 由共享 HTML 约定（handle-lifecycle.html 读 `payload.uri`）。
 */
export function handleUriPayload(uri: string): string {
  return '{"uri":' + jsString(uri) + '}';
}

/**
 * `onHandleUri` 的入参 —— **裸字符串，不是对象**。
 *
 * 与 `handleUriPayload` 只差一层包装，但两个回调的契约确实不同，共享 HTML 里写死了：
 * - `onRegister(payload)` 读 `payload.uri` → 要对象（`handleUriPayload`）
 * - `onHandleUri(uri)` 直接把参数拼进 `<img src="${uri}">` → 要裸字符串（本函数）
 *
 * 用错会静默出错：对象被拼进模板串就成了 `[object Object]`，浏览器拿它当相对路径去请求，
 * 真机上表现为 `ERR_FILE_NOT_FOUND ← resource://rawfile/demo/pages/[object%20Object]`
 * —— 图片位置只是一张碎图，不会有任何提示指向真正的原因。Android 侧对应的是
 * `JSONObject.quote(uri)`，同样是裸字符串。
 */
export function handleUriString(uri: string): string {
  return jsString(uri);
}

/**
 * `onRegister` 的失败形态。共享 HTML 只读 `payload.uri`，所以这里同时给出
 * `ok:false` 与一条空 uri —— 页面不会拿到一条假 URI 去 render。
 */
export function handleRegisterFailurePayload(message: string): string {
  return '{"ok":false,"uri":"","message":' + jsString(message) + '}';
}

/**
 * 场景 5（§13.5）`onResult` 的 payload：`{"kind": "...", "result": {...}}`。
 *
 * 与 `engineResultPayload` 刻意不同形：那条服务于 §13.3/§13.4 的 `onProbe`
 * （成功即 `{"ok":true}`，不带 category），而 error-categories.html 无条件读
 * `r.category` / `r.stage` / `r.message` 三个字段来填表格 —— 成功分支若不给
 * category，那一格会显示 `undefined`。
 *
 * 成功时的 `category: "OK"` / `message: "resolved"` 逐字对齐 Android
 * `ErrorCategoriesActivity`：它不是 ResourceErrorCategory 的成员，而是"这条探针
 * 本该失败却成功了"的哨兵值 —— 四条探针任何一条显示 OK 都意味着演示失真。
 *
 * 失败分支直接取 `EngineFailure` 自带的 category / stage / reason，
 * 不做任何再分类（§13.5 明确要求「复用正式 EngineResult 失败态的 category + stage」）。
 */
export function errorProbePayload(kind: string, result: EngineResult): string {
  let inner: string;
  if (result.kind === 'success') {
    inner = '{"category":"OK","stage":null,"message":"resolved"}';
  } else {
    const stageJson = result.stage === null ? 'null' : jsString(result.stage);
    inner = '{"category":' + jsString(String(result.category)) +
      ',"stage":' + stageJson +
      ',"message":' + jsString(result.reason) + '}';
  }
  return '{"kind":' + jsString(kind) + ',"result":' + inner + '}';
}

/**
 * 场景 8（§13.8）`onChooseSuccess` 的 payload。
 *
 * `previewUri` 是 `registerHandle` 铸造的**可解析、可反查**的 capability URI ——
 * 页面把它直接塞进 `<img src>` 预览，提交时再原样回传。字段名由
 * shared/demo/pages/jsbridge-image-picker.html 约定（读 `payload.previewUri`
 * 与 `payload.fileName`），三端共用同一份 HTML。
 */
export function choosePayload(previewUri: string, fileName: string, mimeType: string): string {
  return '{"previewUri":' + jsString(previewUri) +
    ',"fileName":' + jsString(fileName) +
    ',"mimeType":' + jsString(mimeType) + '}';
}

/**
 * 场景 8（§13.8）`onSubmitSuccess` 的 payload。
 *
 * §13.8 逐条点名了提交后必须展示的五个字段：`contentUri`、`localCachePath`、
 * `fileName`、`mimeType`、`size`。它们全部来自 native 用 `previewUri` **反查**
 * 回来的 handle 记录，而不是 Web 侧回传的内容 —— 这正是本场景要证明的
 * 「由资源 URI 反查 Native 资源句柄」。
 *
 * `size` 是数字，不加引号：页面把整个 payload 原样 JSON.stringify 出来展示，
 * 引号会让它看起来像字符串长度而非字节数。
 */
export function submitPayload(
  previewUri: string,
  contentUri: string,
  localCachePath: string,
  fileName: string,
  mimeType: string,
  size: number,
): string {
  return '{"previewUri":' + jsString(previewUri) +
    ',"contentUri":' + jsString(contentUri) +
    ',"localCachePath":' + jsString(localCachePath) +
    ',"fileName":' + jsString(fileName) +
    ',"mimeType":' + jsString(mimeType) +
    ',"size":' + String(size) + '}';
}

/**
 * 场景 8 的两条错误回调（`onChooseError` / `onSubmitError`）参数是**裸字符串**，
 * 不是对象 —— 页面把它包进 `new Error(message)`。所以这里返回的是一个 JS 字符串
 * 字面量，不是 JSON 对象。
 *
 * `ResourceException` 带 category 时前缀上它，让「提交了一条已失效的 previewUri」
 * 在页面上直接显示为 `RESOLUTION_ERROR: ...` 而不是一句无从归类的话。
 */
export function bridgeErrorMessage(error: Object, fallback: string): string {
  if (error instanceof ResourceException) {
    return jsString(String(error.category) + ': ' + error.message);
  }
  if (error instanceof Error) {
    return jsString(error.message.length > 0 ? error.message : fallback);
  }
  return jsString(fallback);
}

/**
 * 拼一条调用 `window.LocalAssetSampleNative.<callback>(<payload>)` 的语句。
 *
 * 加 `window.LocalAssetSampleNative &&` 短路：页面还没执行到定义这个对象的脚本时
 * （例如 native 侧比 DOMContentLoaded 更早回调），直接调用会抛 TypeError，
 * 在 runJavaScript 里表现为一条无人处理的 rejected promise。
 */
export function dispatchScript(callback: string, payload: string): string {
  return 'window.LocalAssetSampleNative && window.LocalAssetSampleNative.' +
    callback + '(' + payload + ');';
}
