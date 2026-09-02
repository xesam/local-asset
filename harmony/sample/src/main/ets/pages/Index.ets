import common from '@ohos.app.ability.common';
import { webview } from '@kit.ArkWeb';
import { EngineFailureInfo } from 'io.github.xesam.harmony.localasset.core';
import { LocalAssetSchemeHandler, HarmonyResolveContextFactory } from 'io.github.xesam.harmony.localasset.webview';
import { DemoEngine, ENGINE_SCOPE } from '../common/DemoEngine';
import { DemoBridge } from '../common/DemoBridge';

const RAWFILE_PREFIX = 'resource://rawfile/demo/pages/';
const INDEX_PAGE = RAWFILE_PREFIX + 'index.html';

/**
 * 整个示例应用的**唯一**页面：一块全屏 Web 组件。
 *
 * ## 为什么只剩一个
 *
 * demo 是一个完整的 web 应用，首页（`demo/pages/index.html`）也是它的一页，页间跳转
 * 由 HTML 里的 `<a href>` 完成。原生只负责三件事，都不是「演示内容」：
 *
 * 1. 装载 Web 组件并挂上 scheme handler
 * 2. 构建引擎（见 `common/DemoEngine.ets`）
 * 3. 实现 JSBridge（见 `common/DemoBridge.ets`）—— 选图这类**只有原生能做**的事
 *
 * 演示的标题、说明、分组、按钮全部在共享 HTML 里，三端加载同一份，因此三端长得一样。
 * 曾经这里有一个原生列表页 + 8 个 @Entry 场景页，每端各写一套 —— 那正是三端外观不一致的根因。
 *
 * ## 时序（本模块最容易踩、且踩了不报错的坑）
 *
 * 两次注册分属两个不同时刻，顺序不能颠倒：
 *
 * 1. `webview.WebviewController.customizeSchemes([...])` 是 **static** 方法，作用于整个
 *    Web 内核，必须**早于任何 Web 组件初始化**。已在 `EntryAbility.onCreate` 里执行。
 *    晚了则注册不报错但不生效 —— 表现为请求根本进不了 handler。
 * 2. `controller.setWebSchemeHandler(...)`（即 `attachTo`）是 **实例** 方法，必须**晚到
 *    controller 已与组件绑定之后**，故写在 `onControllerAttached` 里。早于它调用会抛
 *    「controller 尚未与组件绑定」。
 *
 * **维护约束**：不要把任何演示文案搬回本文件。屏幕上该出现的字，都属于 `shared/demo/`。
 * 另外，ArkUI 页面在本仓没有任何测试手段（无设备、无 UI 测试 harness），`hvigorw test`
 * 只会编译它 —— 凡是有真值可断言的逻辑都应下沉到 `common/` 下那几个有单测的文件。
 */
@Entry
@Component
struct Index {
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private controller: webview.WebviewController = new webview.WebviewController();
  private engine: DemoEngine = new DemoEngine(this.context);

  private assetHandler: LocalAssetSchemeHandler | null = null;
  /**
   * 注入给页面的桥。在 aboutToAppear 里定型一次，**不要挪进 build()** ——
   * build() 会在每次 @State 变化时重跑；若在那里新建 JavaScriptProxy 字面量，
   * 每次状态更新都会给 Web 组件换上一个新的 proxy 配置，可能触发桥的重新注册，
   * 而 lastFailure 恰恰在演示失败时才变化，也就是最需要桥继续可用的时刻。
   *
   * **只注入一个名字**：`javaScriptProxy` 是 ArkUI 的属性方法，**连调两次不是注册
   * 两个桥，而是后者覆盖前者**。共享 HTML 用到两个名字（多数页面调
   * `NativeSampleBridge`，`graceful-degradation.html` 调 `LocalAssetSampleBridge`），
   * 名字对不上时页面脚本抛 `TypeError: undefined is not an object`，**整段 script
   * 当场中断** —— 那些页面的内容都由脚本生成，于是表现为一片空白，没有任何提示。
   * 故第二个名字改用 `registerJavaScriptProxy` 在 controller 绑定后补注册。
   */
  private proxy: JavaScriptProxy | null = null;

  private bridge: DemoBridge | null = null;

  @State private lastFailure: string = '';

  aboutToAppear(): void {
    const bridge = new DemoBridge(
      this.context,
      this.engine.localAsset,
      this.engine.revokedHandleUri,
      (script: string) => {
        this.controller.runJavaScript(script);
      },
      () => {
        this.controller.refresh();
      },
    );

    this.assetHandler = new LocalAssetSchemeHandler({
      engine: this.engine.localAsset.engine,
      contextFactory: new HarmonyResolveContextFactory(ENGINE_SCOPE),
      // release 构建里唯一可靠的观测通道（LoggingEngineObserver 走 hilog，常被级别过滤丢弃）。
      onFailure: (failure: EngineFailureInfo) => {
        this.lastFailure = String(failure.category) + ' @ ' + (failure.stage ?? '-') +
          ' — ' + failure.reason;
      },
    });

    this.bridge = bridge;
    this.proxy = {
      object: bridge,
      name: 'NativeSampleBridge',
      methodList: DemoBridge.methodList(),
      controller: this.controller,
    };
  }

  /**
   * WebView 有历史就先退一页，否则才退出应用。
   *
   * 页间跳转由共享 HTML 承担，系统返回键若不拦截，
   * 从任一场景页按返回就直接退出应用而不是回到首页 —— 与 Android 侧行为不一致。
   *
   * `accessBackward()` 会在 controller 尚未与 Web 组件绑定时抛 BusinessError 17100001。
   * 本回调理应只在页面显示后触发（那时绑定已完成），但生命周期回调里逃逸的异常会**让
   * ability 崩溃**而不是干净退出，代价远大于兜底成本；Android 的 `canGoBack()` 不会抛，
   * 不兜底就成了三端行为差异。catch 里返回 false 交还系统，与「无历史可退」同一路径，
   * 即降级为系统默认的退出行为。
   *
   * 返回 true 表示事件已消费；返回 false 交还系统（此时已在首页，退出是对的）。
   */
  onBackPress(): boolean {
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        return true;
      }
    } catch (err) {
      // 17100001: controller 未绑定组件。降级交还系统，不让异常掀掉 ability。
    }
    return false;
  }

  build() {
    Column() {
      if (this.lastFailure.length > 0) {
        Text('last failure: ' + this.lastFailure)
          .fontSize(11)
          .fontColor('#dc2626')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .width('100%')
      }
      Web({ src: INDEX_PAGE, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .javaScriptProxy(this.proxy)
        .onControllerAttached(() => {
          // setWebSchemeHandler 是实例方法，早于本回调调用会抛「controller 尚未与组件绑定」；
          // scheme 本身已在 EntryAbility.onCreate 里经 customizeSchemes 注册，两个时序不能颠倒。
          this.assetHandler?.attachTo(this.controller);
          // 第二个桥名在这里补注册 —— javaScriptProxy 属性连调两次是覆盖而非叠加。
          //
          // **不要在这里调 refresh()**：refresh 会重新触发 onControllerAttached，
          // 于是 attach → refresh → attach → refresh 无限循环，真机上表现为
          // "Err too many redirects"。本回调早于首页加载，注册赶得上，无需刷新。
          if (this.bridge !== null) {
            this.controller.registerJavaScriptProxy(
              this.bridge, 'LocalAssetSampleBridge', DemoBridge.methodList());
          }
        })
        .layoutWeight(1)
        .width('100%')
    }
    .width('100%')
    .height('100%')
  }
}
