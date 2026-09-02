import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import {
  LocalAsset,
  ResourceHandleRecord,
  EngineResult,
  createResourceHandle,
  createResolveContext,
  bytesSource,
} from 'io.github.xesam.harmony.localasset.core';
import { sandboxDir, writeBytes, ensureDir, readRawfileBytes } from './SampleFiles';
import {
  dispatchScript,
  choosePayload,
  submitPayload,
  bridgeErrorMessage,
  handleUriPayload,
  handleUriString,
  handleRegisterFailurePayload,
  probeOkPayload,
  handleExceptionPayload,
  engineResultPayload,
  errorProbePayload,
} from './BridgePayloads';
import { fileNameFromPickerUri, guessImageMime, submittedFileName } from './PickedImage';
import { errorProbeUrl } from './ErrorProbes';
import { ENGINE_SCOPE, LOGO_RAWFILE } from './DemoEngine';

/**
 * 从 handle 记录里取回原始选图 URI 用的 metadata key。
 *
 * **属于 HarmonyOS 宿主约定，不是跨平台正式契约** —— 与 Android 的
 * `android.content_uri` 一一对应（§13.8 明写这层对应关系）。
 * 库本身不认识这个 key：`metadata` 对 core 而言只是一张不透明的字符串表。
 */
const PICKER_URI_KEY = 'harmony.picker_uri';

/** 提交后落地文件所在的沙箱子目录。 */
const SUBMIT_DIR_NAME = 'bridge-submitted';

/**
 * 八个场景共用的 JSBridge。
 *
 * 合并前每个 @Entry 页各挂一个只含自己那几个方法的桥；现在只有一块 Web 组件，故合成一个
 * —— 页面只调自己需要的方法，多出来的方法对它无副作用。
 *
 * ## 两条硬约束
 *
 * 1. **方法名必须与 `shared/demo/pages/*.html` 里的调用逐字对应**，且必须原样出现在
 *    注入时的 `methodList` 里 —— ArkWeb 只暴露 methodList 中列出的方法，漏一个就是
 *    「点了没反应」，没有任何提示。
 * 2. **每条调用路径都必须恰好回调一次**。选图与提交在页面侧被包成 Promise，
 *    任何一条静默返回都会让 await 永远挂着，按钮从此失效。
 *
 * 写成普通 class 而非 struct 内部逻辑，是为了让它能脱离 UI 独立构造；有真值可断言的
 * 部分（payload 构造、文件名推导）已进一步下沉到 `BridgePayloads.ets` / `PickedImage.ets`，
 * 那两个文件有单测覆盖，本文件只剩编排。
 */
export class DemoBridge {
  private readonly context: common.UIAbilityContext;
  private readonly localAsset: LocalAsset;
  private readonly dispatch: (script: string) => void;
  private readonly reload: () => void;
  private readonly revokedHandleUri: string;

  /** 本次会话注册过的全部句柄 URI，`resetSession` 一次性吊销。 */
  private readonly registeredUris: Set<string> = new Set<string>();

  constructor(
    context: common.UIAbilityContext,
    localAsset: LocalAsset,
    revokedHandleUri: string,
    dispatch: (script: string) => void,
    reload: () => void,
  ) {
    this.context = context;
    this.localAsset = localAsset;
    this.revokedHandleUri = revokedHandleUri;
    this.dispatch = dispatch;
    this.reload = reload;
  }

  /** 注入时要用的方法名清单 —— 与本类的公开方法一一对应，漏一个即静默失效。 */
  static methodList(): string[] {
    return [
      'resetSession',
      'registerHandle', 'revokeHandle', 'probeResolveHandle',
      'getHandleUri', 'probeResolve',
      'trigger',
      'getRevokedHandleUri',
      'chooseImage', 'submitImage',
    ];
  }

  // ---- 通用（替代原先的原生页头按钮）----

  /** 撤销本次会话注册的全部句柄后刷新。对应原生页头上那个 Reset / Reset Session 按钮。 */
  resetSession(): void {
    this.registeredUris.forEach((uri: string) => {
      this.localAsset.removeHandle(uri);
    });
    this.registeredUris.clear();
    this.reload();
  }

  // ---- handle-lifecycle ----

  registerHandle(ttlSeconds: number): void {
    const bytes: Uint8Array | null = readRawfileBytes(this.context, LOGO_RAWFILE);
    if (bytes === null) {
      this.dispatch(dispatchScript(
        'onRegister',
        handleRegisterFailurePayload('rawfile missing: ' + LOGO_RAWFILE),
      ));
      return;
    }
    const uri: string = this.localAsset.registerHandle(createResourceHandle({
      source: bytesSource(bytes),
      fileName: 'logo.svg',
      mimeType: 'image/svg+xml',
      ttlMillis: ttlSeconds * 1000,
    }));
    this.registeredUris.add(uri);
    this.dispatch(dispatchScript('onRegister', handleUriPayload(uri)));
  }

  /** 未知 URI 是 no-op（正式 registry 语义）。 */
  revokeHandle(uri: string): void {
    this.localAsset.removeHandle(uri);
    this.registeredUris.delete(uri);
    this.dispatch(dispatchScript('onRevoke', '{}'));
  }

  /**
   * §13.3 要求的原生探测入口：把「URI 是否仍解析」变成**可见结论**。
   * 碎图只说明请求失败，说不出 category 与 stage。
   */
  probeResolveHandle(uri: string): void {
    try {
      this.localAsset.resolveHandle(uri);
      this.dispatch(dispatchScript('onProbe', probeOkPayload()));
    } catch (error) {
      this.dispatch(dispatchScript('onProbe', handleExceptionPayload(error)));
    }
  }

  // ---- security-models ----

  /**
   * 每次调用都新注册一条：本方法在 DOMContentLoaded 里被调用，用户可能反复进出该页，
   * 沿用一条会话级 URI 会在 resetSession 之后失效。
   */
  getHandleUri(): void {
    const bytes: Uint8Array | null = readRawfileBytes(this.context, LOGO_RAWFILE);
    const uri: string = this.localAsset.registerHandle(createResourceHandle({
      source: bytesSource(bytes ?? new Uint8Array(0)),
      fileName: 'logo.svg',
      mimeType: 'image/svg+xml',
    }));
    this.registeredUris.add(uri);
    this.dispatch(dispatchScript('onHandleUri', handleUriString(uri)));
  }

  probeResolve(url: string): void {
    const result: EngineResult = this.localAsset.engine.resolveUrl(
      url,
      createResolveContext({ engineScope: ENGINE_SCOPE }),
    );
    this.dispatch(dispatchScript('onProbe', engineResultPayload(result)));
  }

  // ---- error-categories ----

  trigger(kind: string): void {
    const url: string | null = errorProbeUrl(kind);
    if (url === null) {
      return;
    }
    const result: EngineResult = this.localAsset.engine.resolveUrl(
      url,
      createResolveContext({ engineScope: ENGINE_SCOPE }),
    );
    this.dispatch(dispatchScript('onResult', errorProbePayload(kind, result)));
  }

  // ---- graceful-degradation ----

  /** 同步返回 —— 该页在**顶层脚本**里直接取返回值，早于 DOMContentLoaded，不走回调。 */
  getRevokedHandleUri(): string {
    return this.revokedHandleUri;
  }

  // ---- jsbridge-image-picker ----

  /**
   * 声明成同步方法（返回 void）而不是 async：ArkWeb 的 JavaScriptProxy 只把方法
   * **调用**转发过去，返回的 Promise 无人接收；结果一律通过 runJavaScript 回调送回。
   */
  chooseImage(): void {
    const picker = new photoAccessHelper.PhotoViewPicker();
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    picker.select(options)
      .then((selection: photoAccessHelper.PhotoSelectResult) => {
        this.onPicked(selection.photoUris);
      })
      .catch((error: Object) => {
        // 用户取消在部分版本上表现为 reject 而非空数组，两条路径都必须回调一次。
        this.dispatchError('onChooseError', error, 'Image picking was cancelled');
      });
  }

  /** 回传的是 **URI** 而不是 token：先反查回原记录，再基于记录落地文件。 */
  submitImage(previewUri: string): void {
    try {
      const record: ResourceHandleRecord = this.localAsset.resolveHandle(previewUri);
      const source = record.source;
      if (source.kind !== 'bytes') {
        throw new Error('preview handle is not bytes-backed');
      }
      const pickerUri: string = record.metadata.get(PICKER_URI_KEY) ?? '';
      const destDir: string = sandboxDir(this.context, SUBMIT_DIR_NAME);
      ensureDir(destDir);
      const destPath: string = destDir + '/' + submittedFileName(record.fileName);
      writeBytes(destPath, source.value);
      // size 取写入后的 stat 而非 record.size：二者理应相等，取 stat 才能证明
      // 这个「业务可用落地文件」真的存在（§13.8 对 localCachePath 的要求）。
      const size: number = fs.statSync(destPath).size;
      this.dispatch(dispatchScript('onSubmitSuccess', submitPayload(
        record.resourceUri,
        pickerUri,
        destPath,
        record.fileName,
        record.mimeType,
        size,
      )));
    } catch (error) {
      this.dispatchError('onSubmitError', error, 'Unknown submit error');
    }
  }

  private onPicked(photoUris: string[]): void {
    if (photoUris.length === 0) {
      this.dispatch(dispatchScript('onChooseError', '"Image picking was cancelled"'));
      return;
    }
    try {
      const sourceUri: string = photoUris[0];
      const bytes: Uint8Array = readFileBytes(sourceUri);
      const fileName: string = fileNameFromPickerUri(sourceUri);
      const mimeType: string = guessImageMime(fileName);
      const metadata: Map<string, string> = new Map<string, string>();
      metadata.set(PICKER_URI_KEY, sourceUri);
      const previewUri: string = this.localAsset.registerHandle(createResourceHandle({
        source: bytesSource(bytes),
        fileName: fileName,
        mimeType: mimeType,
        metadata: metadata,
      }));
      this.registeredUris.add(previewUri);
      this.dispatch(dispatchScript(
        'onChooseSuccess',
        choosePayload(previewUri, fileName, mimeType),
      ));
    } catch (error) {
      this.dispatchError('onChooseError', error, 'Unknown image error');
    }
  }

  /** 两条错误回调的参数是**裸字符串**（页面把它包进 `new Error(message)`），不是 JSON 对象。 */
  private dispatchError(callback: string, error: Object, fallback: string): void {
    this.dispatch(dispatchScript(callback, bridgeErrorMessage(error, fallback)));
  }
}

/**
 * 按 URI 读整个文件。
 *
 * photoAccessHelper 给的是 `file://media/...` 形态的 URI，`fs.openSync` 直接受理。
 * fd 的归还放在 finally：`statSync(fd)` 或 `readSync` 抛出时同样必须关闭，
 * 否则每次失败泄漏一个 fd（与 core `FileResourceLoader` 同一条理由、同一个写法）。
 */
function readFileBytes(uri: string): Uint8Array {
  const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    const stat = fs.statSync(file.fd);
    const buffer = new ArrayBuffer(stat.size);
    fs.readSync(file.fd, buffer);
    return new Uint8Array(buffer);
  } finally {
    fs.closeSync(file);
  }
}
