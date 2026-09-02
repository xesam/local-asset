import UIAbility from '@ohos.app.ability.UIAbility';
import window from '@ohos.window';
import { webview } from '@kit.ArkWeb';
import { localAssetCustomScheme } from 'io.github.xesam.harmony.localasset.webview';

export default class EntryAbility extends UIAbility {
  onCreate(): void {
    // 自定义 scheme 必须在任何 Web 组件初始化之前注册，越早越好。
    // 放在 onCreate 里能覆盖所有演示页面 —— 晚于 Web 内核初始化再注册会静默失败，
    // 表现为请求永远到不了 handler。
    // 与之相对：controller.setWebSchemeHandler(...) 必须在 onControllerAttached 之后调用。
    webview.WebviewController.customizeSchemes([localAssetCustomScheme()]);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index');
  }
}
