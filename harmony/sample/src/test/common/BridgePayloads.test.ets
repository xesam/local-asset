import { describe, it, expect } from '@ohos/hypium';
import {
  jsString,
  probeOkPayload,
  probeFailurePayload,
  engineResultPayload,
  handleExceptionPayload,
  handleUriPayload,
  handleUriString,
  handleRegisterFailurePayload,
  errorProbePayload,
  choosePayload,
  submitPayload,
  bridgeErrorMessage,
  dispatchScript,
} from '../../main/ets/common/BridgePayloads';
import {
  engineSuccess,
  engineFailure,
  createResourceDescriptor,
  ResourceDescriptor,
  bytesData,
  bytesSource,
  ResourceType,
  ResourceErrorCategory,
  ResourceException,
} from 'io.github.xesam.harmony.localasset.core';

/**
 * 演示页回给 H5 的那几条 payload。
 *
 * 这是四个演示场景中唯一有真值可断言的逻辑 —— ArkUI 页面在本仓没有任何测试手段
 * （无设备、无 UI 测试 harness），`hvigorw test` 只会编译它们。把 payload 构造
 * 从 @Component 里拆出来，正是为了让这部分能被真正验证。
 *
 * 断言的核心是**两条跨端契约**：
 *  1. 回调 payload 的字段形状（ok / category / stage / message / uri）由
 *     shared/demo/pages/*.html 约定，三端共用同一份 HTML；
 *  2. 失败 payload 里的 category 与 stage 必须是引擎/注册表**原样给出**的值，
 *     不允许 sample 侧再分类（compatibility.md §13.3 / §13.5）。
 */

function descriptor(): ResourceDescriptor {
  return createResourceDescriptor({
    id: 'x',
    namespace: 'demo',
    type: ResourceType.STATIC,
    source: bytesSource(new Uint8Array([1])),
    createdAtMillis: 0,
  });
}

export default function bridgePayloadsTest() {
  describe('BridgePayloads', () => {
    it('jsString produces a quoted JS string literal', 0, () => {
      expect(jsString('abc')).assertEqual('"abc"');
    });

    it('jsString escapes quotes and backslashes so the script stays parseable', 0, () => {
      expect(jsString('a"b')).assertEqual('"a\\"b"');
      expect(jsString('a\\b')).assertEqual('"a\\\\b"');
    });

    it('jsString escapes U+2028 / U+2029, which JSON.stringify leaves raw', 0, () => {
      // 经典的 JSON-in-JS 陷阱：这两个字符在 JSON 里合法，在 JS 源码里是换行符，
      // 原样拼进 runJavaScript 会把语句拦腰截断。
      expect(jsString('a\u2028b')).assertEqual('"a\\u2028b"');
      expect(jsString('a\u2029b')).assertEqual('"a\\u2029b"');
    });

    it('probeOkPayload is the minimal ok shape the shared HTML checks', 0, () => {
      expect(probeOkPayload()).assertEqual('{"ok":true}');
    });

    it('probeFailurePayload carries category, stage and message', 0, () => {
      const payload = probeFailurePayload('SECURITY_ERROR', 'policy_post', 'engine scope mismatch');
      expect(payload).assertEqual(
        '{"ok":false,"category":"SECURITY_ERROR","stage":"policy_post","message":"engine scope mismatch"}',
      );
    });

    it('probeFailurePayload emits JSON null for a missing stage', 0, () => {
      // 共享 HTML 用 `payload.stage ?? "-"` 兜底，所以这里必须是 null 而不是 "null"。
      const payload = probeFailurePayload('PARSE_ERROR', null, 'invalid url');
      expect(payload).assertEqual('{"ok":false,"category":"PARSE_ERROR","stage":null,"message":"invalid url"}');
    });

    it('engineResultPayload maps a success to the ok shape', 0, () => {
      const payload = engineResultPayload(
        engineSuccess(descriptor(), bytesData(new Uint8Array([1]), 'image/svg+xml')),
      );
      expect(payload).assertEqual('{"ok":true}');
    });

    it('engineResultPayload passes the engine category and stage through unchanged', 0, () => {
      // §13.4 / §13.5：必须复用正式 EngineResult 失败态的 category + stage，
      // 而不是 sample 自造分类。
      const failure = engineFailure(
        ResourceErrorCategory.SECURITY_ERROR,
        'engine scope mismatch',
        'policy_post',
      );
      const payload = engineResultPayload(failure);
      expect(payload).assertEqual(
        '{"ok":false,"category":"SECURITY_ERROR","stage":"policy_post","message":"engine scope mismatch"}',
      );
    });

    it('engineResultPayload keeps a null stage as null', 0, () => {
      const failure = engineFailure(ResourceErrorCategory.LOAD_ERROR, 'boom', null);
      expect(payload_stage(engineResultPayload(failure))).assertEqual('null');
    });

    it('handleExceptionPayload defaults a stage-less registry error to stage resolve', 0, () => {
      // InMemoryHandleRegistry 抛的 ResourceException 不带 stage（它不在引擎流水线里），
      // 但 §13.3 要求这条失败对外表现为 RESOLUTION_ERROR @ resolve —— 与同一条 URI
      // 走 WebView 请求时引擎给出的阶段一致。缺省必须补在这里。
      const error = new ResourceException(
        ResourceErrorCategory.RESOLUTION_ERROR,
        'Unknown or expired resourceUri: local-asset://h/handles/t/logo.svg',
      );
      const payload = handleExceptionPayload(error);
      expect(payload_field(payload, 'category')).assertEqual('"RESOLUTION_ERROR"');
      expect(payload_field(payload, 'stage')).assertEqual('"resolve"');
    });

    it('handleExceptionPayload keeps an explicit stage rather than overwriting it', 0, () => {
      const error = new ResourceException(ResourceErrorCategory.SECURITY_ERROR, 'nope', 'policy_post');
      const payload = handleExceptionPayload(error);
      expect(payload_field(payload, 'category')).assertEqual('"SECURITY_ERROR"');
      expect(payload_field(payload, 'stage')).assertEqual('"policy_post"');
    });

    it('handleExceptionPayload maps a non-ResourceException to RESOLUTION_ERROR', 0, () => {
      // 探测入口的语义是「这条凭证还能不能换到资源」；任何异常的答案都是不能。
      const payload = handleExceptionPayload(new Error('unexpected'));
      expect(payload_field(payload, 'category')).assertEqual('"RESOLUTION_ERROR"');
      expect(payload_field(payload, 'stage')).assertEqual('"resolve"');
      expect(payload_field(payload, 'message')).assertEqual('"unexpected"');
    });

    /**
     * 两个回调的形态**不同**，共享 HTML 里写死了，用错会静默出错：
     * onRegister 读 payload.uri（要对象），onHandleUri 直接把参数拼进 `<img src>`（要裸串）。
     * 传错时对象被拼成 `[object Object]`，真机只表现为一张碎图 —— 实测踩过。
     */
    it('handleUriString is a bare string, not an object', 0, () => {
      const uri = 'local-asset://security.demo.local/handles/t/logo.svg';
      expect(handleUriString(uri)).assertEqual('"' + uri + '"');
      // 与对象形态确实不同 —— 这条断言防的正是"两个函数被写成同一个实现"。
      expect(handleUriString(uri) === handleUriPayload(uri)).assertFalse();
    });

    it('handleUriPayload uses the uri field the shared HTML reads', 0, () => {
      const uri = 'local-asset://lifecycle.demo.local/handles/abc/logo.svg';
      expect(handleUriPayload(uri)).assertEqual('{"uri":"' + uri + '"}');
    });

    it('handleRegisterFailurePayload never hands the page a fabricated uri', 0, () => {
      const payload = handleRegisterFailurePayload('rawfile missing');
      expect(payload_field(payload, 'uri')).assertEqual('""');
      expect(payload_field(payload, 'ok')).assertEqual('false');
    });

    it('dispatchScript guards against the callback object not existing yet', 0, () => {
      // native 侧可能早于页面脚本执行；无短路时直接调用会抛 TypeError，
      // 在 runJavaScript 里变成一条无人处理的 rejected promise。
      const script = dispatchScript('onProbe', '{"ok":true}');
      expect(script).assertEqual(
        'window.LocalAssetSampleNative && window.LocalAssetSampleNative.onProbe({"ok":true});',
      );
    });

    // ---- §13.5 error-categories ------------------------------------------------

    it('errorProbePayload nests the result under the kind the table row keys on', 0, () => {
      // error-categories.html 用 payload.kind 找到那一行的三个 <td>
      // （cat-${kind} / stage-${kind} / msg-${kind}），再读 payload.result 填它们。
      const failure = engineFailure(ResourceErrorCategory.LOAD_ERROR, 'file source is not readable', 'load');
      const payload = errorProbePayload('load', failure);
      expect(payload).assertEqual(
        '{"kind":"load","result":{"category":"LOAD_ERROR","stage":"load",' +
        '"message":"file source is not readable"}}',
      );
    });

    it('errorProbePayload passes engine category and stage through unchanged', 0, () => {
      // §13.5：必须复用正式 EngineResult 失败态的 category + stage，不得自造分类。
      const failure = engineFailure(
        ResourceErrorCategory.SECURITY_ERROR,
        'engine scope mismatch',
        'policy_post',
      );
      const payload = errorProbePayload('security', failure);
      expect(payload_field(payload, 'category')).assertEqual('"SECURITY_ERROR"');
      expect(payload_field(payload, 'stage')).assertEqual('"policy_post"');
    });

    it('errorProbePayload emits JSON null for a stage-less failure', 0, () => {
      // 页面用 `r.stage ?? "—"` 兜底，所以必须是 null 而非字符串 "null"。
      const failure = engineFailure(ResourceErrorCategory.PARSE_ERROR, 'invalid url', null);
      expect(payload_stage(errorProbePayload('parse', failure))).assertEqual('null');
    });

    it('errorProbePayload marks an unexpected success with the OK sentinel', 0, () => {
      // 页面无条件读 r.category，成功分支若不给它，那一格会显示 undefined。
      // "OK" 不是 ResourceErrorCategory 的成员 —— 它是「这条探针本该失败却成功了」
      // 的哨兵值（逐字对齐 Android ErrorCategoriesActivity），任何一行显示它
      // 都意味着演示失真。
      const payload = errorProbePayload(
        'parse',
        engineSuccess(descriptor(), bytesData(new Uint8Array([1]), 'image/svg+xml')),
      );
      expect(payload_field(payload, 'category')).assertEqual('"OK"');
      expect(payload_field(payload, 'stage')).assertEqual('null');
      expect(payload_field(payload, 'message')).assertEqual('"resolved"');
    });

    // ---- §13.8 jsbridge-image-picker -------------------------------------------

    it('choosePayload carries the previewUri the page puts straight into <img src>', 0, () => {
      const uri = 'local-asset://bridge.demo.local/preview/tok/IMG_1.jpg';
      const payload = choosePayload(uri, 'IMG_1.jpg', 'image/jpeg');
      expect(payload).assertEqual(
        '{"previewUri":"' + uri + '","fileName":"IMG_1.jpg","mimeType":"image/jpeg"}',
      );
    });

    it('submitPayload exposes all five fields §13.8 names', 0, () => {
      // §13.8：提交后必须展示 contentUri / localCachePath / fileName / mimeType / size。
      const payload = submitPayload(
        'local-asset://bridge.demo.local/preview/tok/IMG_1.jpg',
        'file://media/Photo/1/IMG_1/IMG_1.jpg',
        '/data/cache/bridge-submitted/submitted-IMG_1.jpg',
        'IMG_1.jpg',
        'image/jpeg',
        2048,
      );
      expect(payload_field(payload, 'contentUri')).assertEqual('"file://media/Photo/1/IMG_1/IMG_1.jpg"');
      expect(payload_field(payload, 'localCachePath'))
        .assertEqual('"/data/cache/bridge-submitted/submitted-IMG_1.jpg"');
      expect(payload_field(payload, 'fileName')).assertEqual('"IMG_1.jpg"');
      expect(payload_field(payload, 'mimeType')).assertEqual('"image/jpeg"');
      expect(payload_field(payload, 'size')).assertEqual('2048');
    });

    it('submitPayload keeps size numeric, not quoted', 0, () => {
      // 页面把整个 payload 原样 JSON.stringify 出来展示；加了引号会让字节数
      // 看起来像字符串长度。
      const payload = submitPayload('a', 'b', 'c', 'd', 'e', 0);
      expect(payload_field(payload, 'size')).assertEqual('0');
    });

    it('bridgeErrorMessage prefixes a ResourceException with its category', 0, () => {
      // 提交一条已被 Reset 吊销的 previewUri 时，页面应显示
      // `RESOLUTION_ERROR: Unknown or expired resourceUri: ...` 而不是一句无从归类的话。
      const error = new ResourceException(
        ResourceErrorCategory.RESOLUTION_ERROR,
        'Unknown or expired resourceUri: x',
      );
      expect(bridgeErrorMessage(error, 'fallback'))
        .assertEqual('"RESOLUTION_ERROR: Unknown or expired resourceUri: x"');
    });

    it('bridgeErrorMessage returns a bare JS string literal, not a JSON object', 0, () => {
      // onChooseError / onSubmitError 的参数是裸字符串 —— 页面把它包进 new Error(message)。
      const message = bridgeErrorMessage(new Error('boom'), 'fallback');
      expect(message).assertEqual('"boom"');
      expect(message.startsWith('{')).assertFalse();
    });

    it('bridgeErrorMessage falls back when the error carries no message', 0, () => {
      expect(bridgeErrorMessage(new Error(''), 'Unknown submit error'))
        .assertEqual('"Unknown submit error"');
      expect(bridgeErrorMessage('not an error', 'Unknown image error'))
        .assertEqual('"Unknown image error"');
    });

    it('bridgeErrorMessage escapes quotes so the dispatched script stays parseable', 0, () => {
      // 这条消息会被直接拼进 runJavaScript 的源码里。
      expect(bridgeErrorMessage(new Error('say "hi"'), 'f')).assertEqual('"say \\"hi\\""');
    });
  });
}

/** 从 payload 里抠出某个字段的原始 JSON 文本（避免为了断言引入 JSON.parse 的 any）。 */
function payload_field(payload: string, key: string): string {
  const marker = '"' + key + '":';
  const start = payload.indexOf(marker) + marker.length;
  let end = start;
  if (payload.charAt(start) === '"') {
    end = payload.indexOf('"', start + 1) + 1;
  } else {
    while (end < payload.length && payload.charAt(end) !== ',' && payload.charAt(end) !== '}') {
      end++;
    }
  }
  return payload.substring(start, end);
}

function payload_stage(payload: string): string {
  return payload_field(payload, 'stage');
}
