/**
 * entry 模块的单测入口。
 *
 * hvigor 的 `test` 任务会为每个模块无条件生成 `.test/testability/pages/Index.ets`，
 * 其中硬编码了 `import testsuite from '../../../src/test/List.test'`。
 * 因此这个文件必须存在，否则整个 `hvigorw test` 会在编译期失败，连带把
 * localasset-core / localasset-webview 的测试一起拖挂。
 *
 * ## 这里能测什么、不能测什么
 *
 * **不能测**：`src/main/ets/pages/Index.ets` —— ArkUI 的 @Entry / @Component 在本仓
 * 没有任何测试手段（无设备、无 UI 测试 harness），`hvigorw test` 只会编译它。
 * 演示场景本身现在全部由共享 HTML（`shared/demo/pages/*.html`）承载，
 * 只能由真机/模拟器人工验收覆盖（见 docs/compatibility.md §13.10）。
 *
 * **能测**：那些被刻意从组件里拆出来的纯函数 —— `common/SampleFiles.ets` 的
 * 目录树落地逻辑（靠注入 reader 摆脱 Context 依赖）、`common/BridgePayloads.ets`
 * 的回调 payload 构造、`common/ErrorProbes.ets` 的探针 URL 契约、
 * `common/OverrideBanner.ets` 的 `?mode=` 动态内容、`common/PickedImage.ets` 的
 * 文件名/MIME 派生。给场景加逻辑时，先看看它能不能落到这几个文件里。
 */
import sampleFilesTest from './common/SampleFiles.test';
import bridgePayloadsTest from './common/BridgePayloads.test';
import errorProbesTest from './common/ErrorProbes.test';
import overrideBannerTest from './common/OverrideBanner.test';
import pickedImageTest from './common/PickedImage.test';
import demoEngineTest from './common/DemoEngine.test';

export default function testsuite() {
  sampleFilesTest();
  bridgePayloadsTest();
  errorProbesTest();
  overrideBannerTest();
  pickedImageTest();
  demoEngineTest();
}
