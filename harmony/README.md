# LocalAsset HarmonyOS

协议无关的资源解析引擎 HarmonyOS 端实现。ohpm 包名：`io.github.xesam.harmony.localasset.core` / `io.github.xesam.harmony.localasset.webview`。

## 目录

1. [环境要求](#1-环境要求)
2. [模块说明](#2-模块说明)
3. [构建与测试](#3-构建与测试)
   - [3.1 ⚠️ `hvigorw test` 的退出码不可信](#31-️-hvigorw-test-的退出码不可信)
   - [3.2 ⚠️ 每个注册模块都必须有 `src/test/List.test.ets`，哪怕它一个用例都没有](#32-️-每个注册模块都必须有-srctestlisttestets哪怕它一个用例都没有)
   - [3.3 运行 sample 前必须同步演示内容](#33-运行-sample-前必须同步演示内容)
   - [3.4 签名配置：装真机前需要，跑测试不需要](#34-签名配置装真机前需要跑测试不需要)
4. [快速开始](#4-快速开始)
   - [4.1 注册自定义 scheme（时序关键）](#41-注册自定义-scheme时序关键)
   - [4.2 构建引擎并绑定到 Web 组件](#42-构建引擎并绑定到-web-组件)
   - [4.3 让 FilePath 资源可解析（安全默认）](#43-让-filepath-资源可解析安全默认)
   - [4.4 在 HTML 中引用资源](#44-在-html-中引用资源)
   - [4.5 运行时注册动态资源](#45-运行时注册动态资源)
5. [内置 Resolver](#5-内置-resolver)
6. [生命周期管理](#6-生命周期管理)
7. [失败处理](#7-失败处理)
8. [自定义 scheme](#8-自定义-scheme)
   - [8.1 替换 core 端解析](#81-替换-core-端解析)
   - [8.2 绕过桥接层便捷方法，自行注册](#82-绕过桥接层便捷方法自行注册)
   - [8.3 为什么便捷方法刻意钉死 scheme](#83-为什么便捷方法刻意钉死-scheme)
   - [8.4 注意事项](#84-注意事项)
9. [示例场景](#9-示例场景)
   - [9.1 验收状态（重要）](#91-验收状态重要)
10. [与 Android/iOS 的已知差异](#10-与-androidios-的已知差异)
   - [10.1 不支持 `Stream` 来源与 `AsyncResourceLoader`](#101-不支持-stream-来源与-asyncresourceloader)
   - [10.2 ⚠️ 文件根校验无法消解符号链接（安全相关）](#102-️-文件根校验无法消解符号链接安全相关)
   - [10.3 ⚠️ handle token 熵源：系统 CSPRNG 优先，不可用则 fail-loud](#103-️-handle-token-熵源系统-csprng-优先不可用则-fail-loud)
   - [10.4 本地单元测试沙箱的系统能力限制](#104-本地单元测试沙箱的系统能力限制)
   - [10.5 URL 解析：与参考实现的对齐点与已接受的收窄](#105-url-解析与参考实现的对齐点与已接受的收窄)
   - [10.6 MIME 推断为手写闭表，与两端有取值分叉](#106-mime-推断为手写闭表与两端有取值分叉)
   - [10.7 桥接层集成测试依赖真机/模拟器](#107-桥接层集成测试依赖真机模拟器)
11. [设计参考](#11-设计参考)

---

## 1. 环境要求

- DevEco Studio 26.0.0+（自带 Node、ohpm、hvigor 与 SDK）
- HarmonyOS SDK：工程 `compatibleSdkVersion` 为 `5.0.0(12)`（API 12），本仓库在 API 26 SDK（HarmonyOS 26.0.0 Beta1）上开发验证
- 测试框架：`@ohos/hypium` 1.0.18

## 2. 模块说明

| 模块 | 类型 | 职责 |
|------|------|------|
| `localasset-core` | HAR | 引擎、模型、resolver、registry、policy、loader。零 ArkUI/ArkWeb 依赖。 |
| `localasset-webview` | HAR | 通过 `WebSchemeHandler` 把 `EngineResult` 桥接为 ArkWeb 响应。依赖 core。 |
| `sample` | HAP | 8 个演示场景，与 `docs/compatibility.md §13` 逐条对应。 |

## 3. 构建与测试

`hvigorw` 需要 `DEVECO_SDK_HOME` 与 DevEco 自带的 Node 在 PATH 上：

```bash
cd harmony
export PATH="/Applications/DevEco-Studio.app/Contents/tools/node/bin:$PATH"
export NODE_HOME="/Applications/DevEco-Studio.app/Contents/tools/node"
export DEVECO_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk"

/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm install --all
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw test --no-daemon --rerun-tasks
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --no-daemon
```

`assembleHap` 产物：`harmony/sample/build/default/outputs/default/entry-default-unsigned.hap`（未配置签名时 hvigor 会跳过 `SignHap` 并给出 WARN，属预期）。

推荐直接用仓库根的门禁脚本，它已按下节的判据正确判定三端结果：

```bash
bash scripts/test.sh   # 末行须为 === All tests passed ===
```

当前用例数：`localasset-core` 209、`localasset-webview` 68、`sample` 77，合计 354（数字随用例增补漂移，以 `scripts/test.sh` 实测输出为准）。

### 3.1 ⚠️ `hvigorw test` 的退出码不可信

`hvigorw test` 在**用例断言失败或运行时抛异常时，依然打印 `BUILD SUCCESSFUL` 并返回退出码 0**，
失败只体现在日志行 `ERROR: Error in <用例名>, <原因>`。用 `$?` 判定测试通过与否会得到一个**永远为绿的假门禁**。

权威判据是 hvigor 为每个模块写出的机器可读结果文件：

```text
<module>/.test/default/intermediates/test/coverage_data/test_result.txt
```

末行形如 `Tests run: 209, Failure: 0, Error: 0, Pass: 209, Ignore: 0`。`scripts/test.sh` 的 `run_harmony()` 逐模块校验：

- 日志缺少 `BUILD SUCCESSFUL` → 构建失败（编译错误确实会 exit 255 且不打印该行）
- 结果文件不存在 → 该模块没跑测试，判失败（脚本跑前会先删旧文件，避免读到上一轮的陈旧绿）
- 末行不匹配 `Tests run: [1-9][0-9]*, Failure: 0, Error: 0` → 测试失败

**必须断言 `Tests run` 大于 0**：只 grep 日志里的 `ERROR: Error in` 无法区分「全部通过」与「一个用例都没跑」——
漏把新测试文件注册进 `List.test.ets` 时，两种情况都静默为绿。

### 3.2 ⚠️ 每个注册模块都必须有 `src/test/List.test.ets`，哪怕它一个用例都没有

`hvigorw test` 会为 `build-profile.json5` 里注册的**每一个**模块无条件生成测试承载页
`.test/testability/pages/Index.ets`，其中硬编码 `import testsuite from '../../../src/test/List.test'`。
该文件缺失时整个 `test` 任务在编译期失败（exit 255 / `10505001 ArkTS Compiler Error`），
**并且会把其它模块的测试一起拖挂**——实测：删掉 `sample` 的该文件后，core 与 webview 的用例一个都跑不成。

新增模块时必须同时建一个至少导出空 `testsuite()` 的 `List.test.ets`。

### 3.3 运行 sample 前必须同步演示内容

`shared/demo/` 是三端共享的演示页面。Android 用 Gradle sourceSets 挂载、iOS 用 folder reference，
而 HarmonyOS 的 rawfile 没有等价机制，只能物理复制：

```bash
bash scripts/sync-harmony-demo.sh   # 从仓库根执行
```

复制产物在 `harmony/sample/src/main/resources/rawfile/demo`（20 个文件），已被 gitignore。
该同步也已挂在 sample 的构建流程上，因此 HAP 不会打出空的 rawfile。

### 3.4 签名配置：装真机前需要，跑测试不需要

`build-profile.json5` 里的 `signingConfigs` **在仓库中保持为空**，签名材料放在
gitignore 的 `harmony/signing-config.local.json` 里，由 `harmony/hvigorfile.ts`
在构建期注入 `config.ohos.overrides.signingConfig`。

原因：DevEco Studio 会在首次运行/调试时自动把签名回写进 `build-profile.json5`，
而那份配置的 `certpath` / `profile` / `storeFile` 指向 `~/.ohos/config/` 的绝对路径，
`keyPassword` / `storePassword` 则是能解开 `.p12` 的口令 —— 前者换台机器就不存在，
后者进了 git 历史删不干净。但整个文件又不能忽略：`modules` 与 `products` 是全团队
必须一致的工程结构。所以只外置因人而异的那一段。

**需要装真机时**，两种拿法二选一：

```bash
# A. 让 DevEco 生成后剪切过来（最省事）
#    用 DevEco 打开 harmony/ → File > Project Structure > Signing Configs → 勾选自动签名，
#    DevEco 会把配置写进 build-profile.json5；把其中 signingConfigs[0] 整段剪切到
#    harmony/signing-config.local.json，再把 build-profile.json5 的 signingConfigs 改回 []。

# B. 照模板手填
cp harmony/signing-config.local.json.template harmony/signing-config.local.json
```

**只跑测试则无需任何签名材料**：文件缺失时 `hvigorfile.ts` 直接跳过注入，
`hvigorw test` 与各 HAR 模块构建照常通过（已实测：354 条用例全绿）。
只有 `assembleHap` 会因缺签名失败。

> ⚠️ 注入的 override **只接受 `material` 与 `type` 两个字段**。多带一个 `name` 会让
> 构建以 `Schema validate failed ... propertyName: 'name'` 失败 —— `name` 属于
> `build-profile.json5` 的 `signingConfigs`，不属于 override。`hvigorfile.ts` 已做过滤，
> 所以模板里保留 `name` 也无妨。

## 4. 快速开始

### 4.1 注册自定义 scheme（时序关键）

`customizeSchemes` 是 **static** 方法，作用于整个 Web 内核，进程级只需一次，且必须在**任何 Web 组件初始化之前**调用。
晚于 Web 内核初始化再注册会**静默失败**，表现为请求永远到不了 handler。建议放在 UIAbility 的 `onCreate`：

```typescript
import UIAbility from '@ohos.app.ability.UIAbility';
import { webview } from '@kit.ArkWeb';
import { localAssetCustomScheme } from 'io.github.xesam.harmony.localasset.webview';

export default class EntryAbility extends UIAbility {
  onCreate(): void {
    webview.WebviewController.customizeSchemes([localAssetCustomScheme()]);
  }
}
```

### 4.2 构建引擎并绑定到 Web 组件

绑定 handler 的时序**恰好相反**：`setWebSchemeHandler`（即 `attachTo`）是**实例**方法，
必须在 Web 组件与 controller 绑定**之后**调用，早于 `onControllerAttached` 会抛「controller 尚未与组件绑定」。

```typescript
import { LocalAssetBuilder } from 'io.github.xesam.harmony.localasset.core';
import { LocalAssetSchemeHandler, HarmonyResolveContextFactory, RawfileDirectoryResolver }
  from 'io.github.xesam.harmony.localasset.webview';

const localAsset = new LocalAssetBuilder()
  .addResolver(new RawfileDirectoryResolver({
    host: 'assets.demo.local',
    pathPrefix: '/static',
    rawfileDirectory: 'demo/static',
    // 注入读取函数而非 Context：resourceManager 只能从真实应用 Context 取得，
    // 本地单元测试沙箱里没有 Context，注入后才能用替身覆盖。
    readRawfile: (p: string) => context.resourceManager.getRawFileContentSync(p),
  }))
  .build();

const assetHandler = new LocalAssetSchemeHandler({
  engine: localAsset.engine,
  contextFactory: new HarmonyResolveContextFactory('my-engine'),
  onFailure: (failure) => { /* category + stage + reason */ },
});

Web({ src: pageUrl, controller: this.controller })
  .onControllerAttached(() => { assetHandler.attachTo(this.controller); })
```

`onFailure` 是 **release 构建里唯一可靠的观测通道**——`LoggingEngineObserver` 走 hilog，常被日志级别过滤丢弃。

### 4.3 让 FilePath 资源可解析（安全默认）

与 Android/iOS 一致，`DefaultPolicy` 对 `FilePath` 来源默认 fail-closed：未配置允许根时，
所有文件路径资源都会在 `postCheck` 被拒（`file source is outside allowed roots`）。

```typescript
new LocalAssetBuilder()
  .addAllowedFileRoot(context.cacheDir)
  .build()
```

`addAllowedFileRoot` 只在使用默认 `DefaultPolicy` 时生效；通过 `setPolicy()` 注入自定义策略时该配置被忽略。

### 4.4 在 HTML 中引用资源

```html
<link rel="stylesheet" href="local-asset://assets.demo.local/static/styles.css">
<img src="local-asset://assets.demo.local/static/images/logo.svg">
<script src="local-asset://assets.demo.local/static/app.js"></script>
```

未被 adapter 识别的请求由 `onRequestStart` 返回 `false` 交还 ArkWeb 内核走默认加载路径，无需额外处理。

### 4.5 运行时注册动态资源

```typescript
localAsset.register(createResourceDescriptor({
  id: 'dynamic-1',
  namespace: 'demo',
  type: ResourceType.DYNAMIC,
  source: bytesSource(imageBytes),
  mimeType: 'image/png',
  createdAtMillis: Date.now(),
  ttlMillis: 60_000,
}));
// 此时可通过 local-asset://demo/dynamic-1 解析该资源
```

## 5. 内置 Resolver

| Resolver | 用途 |
|----------|------|
| `RawfileDirectoryResolver` | 映射 `resources/rawfile/` 目录 |
| `FileDirectoryResolver` | 映射沙箱文件目录（如 `context.cacheDir`） |
| `StaticMapResolver` | 特定 URL 映射到特定资源 |
| `RegistryResolver` | 按 ID 查找动态注册资源（链尾兜底） |
| `HandleRegistryResolver` | 反查 Handle-Backed URI（链首） |

链顺序固定，不可通过 Builder 重排：`HandleRegistryResolver` → 用户 `addResolver` 顺序 → `RegistryResolver`。

## 6. 生命周期管理

```typescript
localAsset.unregister('dynamic-1');   // 移除已注册资源
localAsset.removeHandle(uri);         // 显式吊销 handle
localAsset.cleanup();                 // 清理过期资源
localAsset.cleanupHandles();          // 清理过期 handle
```

## 7. 失败处理

- **未进入管线的请求**（非 `local-asset` scheme 或 adapter 无法识别）：`onRequestStart` 返回 `false`，
  交还 ArkWeb 内核 —— 语义对应 Android `shouldInterceptRequest` 返回 `null`。
- **已进入管线并判定失败**：构造 404 响应（`didReceiveResponse` + 空 body + `didFinish`），
  不使用 `didFailWithError` —— 对齐 iOS 的显式失败可见性。

所有失败均带四类错误分类（`PARSE_ERROR`/`RESOLUTION_ERROR`/`LOAD_ERROR`/`SECURITY_ERROR`）与发生阶段，
经 `onFailure` 回调与 hilog 输出。

## 8. 自定义 scheme

默认 scheme `local-asset` 在本端有两处硬编码：core 的 `DefaultLocalAssetSchemeAdapter`（`const SCHEME = 'local-asset'`）与桥接层导出常量 `LOCAL_ASSET_SCHEME`。换 scheme（典型动因：宿主内其他组件已占用 `local-asset`，或需要 URI 形态隔离）需要同时替换这两处，且 ArkWeb 注册环节不能再使用库提供的便捷方法。

### 8.1 替换 core 端解析

实现 `SchemeAdapter` 接口并经 `addAdapter()` 注入。一旦注入任何 adapter，默认 adapter 即完全退出解析（Builder 仅在 adapter 列表为空时回落到 `DefaultLocalAssetSchemeAdapter`）：

```typescript
class MyAssetSchemeAdapter implements SchemeAdapter {
  canHandle(url: string): boolean {
    return url.startsWith('my-asset://');
  }

  parse(url: string): AssetRequest {
    // 解析规则参照 DefaultLocalAssetSchemeAdapter——除 scheme 字面量外逐字段保持一致
    //（含 §9.5 所述的 decode-then-split、'+' 仅 query 解码等对齐点）；
    // AssetRequest.scheme 必须填 URL 的真实 scheme（preCheck 与 handle 回溯都依赖它）
    ...
  }
}

const localAsset = new LocalAssetBuilder()
  .addAdapter(new MyAssetSchemeAdapter())
  .addResolver(...)
  .build();
```

### 8.2 绕过桥接层便捷方法，自行注册

`localAssetCustomScheme()` 与 `attachTo()` 都把 scheme 钉死为 `LOCAL_ASSET_SCHEME`，换 scheme 时不能再用它们。需自行完成 §4.1 的两步注册——时序约束完全不变（进程级注册必须早于任何 Web 组件初始化、挂载必须在 `onControllerAttached` 之后），只是字面量换掉：

```typescript
// ① UIAbility.onCreate，早于任何 Web 组件初始化
const myScheme: webview.WebCustomScheme = {
  schemeName: 'my-asset',
  // 三个开关必须保留：isStandard 决定内核是否按 host（namespace）/path 切分 URL，
  // isSupportCORS / isSupportFetch 决定 H5 fetch()/XHR 能否读取响应
  isSupportCORS: true,
  isSupportFetch: true,
  isStandard: true,
};
webview.WebviewController.customizeSchemes([myScheme]);

// ② onControllerAttached 之后挂 handler
// handler.raw 不判断 scheme 前缀（归属判定在 core adapter 链），可整体复用
controller.setWebSchemeHandler('my-asset', assetHandler.raw);
```

`SchemeRequestHandler` 与 `LocalAssetSchemeHandler.raw` 均不依赖 scheme 字面量，`my-asset://` 请求自动进入同一套管线，§7 的混合失败语义（交还内核 / 404）不变。

### 8.3 为什么便捷方法刻意钉死 scheme

`scheme` 字面量是跨平台契约——改它等于换掉整套 URL 形态（`LocalAssetSchemeHandler.ets` 类注释）。且 ArkWeb 注册是**进程级**的、写错时序**静默失效**；scheme 一旦开放为参数，将同时出现在四处（`customizeSchemes`、`setWebSchemeHandler`、core adapter、`HandleRegistry`），任何一处静默漂移都是「注册了个空 handler」级别的失效。库因此把接入面压缩到两条固定调用，把误配面降到最小；绕过便捷方法即放弃该保护，四处一致性由调用方自负。

### 8.4 注意事项

- **`addAllowedScheme()` 不是换 scheme 的开关**：它只是 `DefaultPolicy` preCheck 的 scheme 白名单（默认空 = 放行所有非空 scheme）。配置了该白名单或注入了自定义 policy 时，确认新 scheme 在放行列表内。
- **Handle 路径的 URI 前缀仍为 `local-asset://`**：`InMemoryHandleRegistry` 铸造的 URI 硬编码该前缀（构造参数仅 host、pathPrefix 可配）。要同时使用自定义 scheme 与 `registerHandle()`，需实现 `HandleRegistry` 接口并经 `setHandleRegistry()` 注入——`resolveFromRequest` 默认实现按 `request.scheme` 重建 URI，铸造与回溯使用同一 scheme 即可闭环。若同时更换 handle host（默认 `DEFAULT_HANDLE_HOST`），需自建 `DefaultPolicy({ handleHost: ... })` 经 `setPolicy()` 注入；Builder 没有该配置项，且注入自定义 policy 后 Builder 的白名单配置全部失效。
- `local-asset` 是三端、H5、共享测试夹具（`docs/compatibility-fixtures/`）与 [Web 侧集成指南](../docs/web-integration.md) 共同固化的跨平台契约；换 scheme 意味着三端与 H5 引用同步迁移，除撞名外不建议更换。

## 9. 示例场景

Sample 应用包含 8 个演示场景，逐条对应 `docs/compatibility.md §13`：

| 场景 | 说明 |
|------|------|
| **静态映射**（§13.1） | `local-asset://assets.demo.local/static/*` 接管 CSS/JS/图片，同屏一张 `https://` 对照图走内核默认路径 |
| **目录路由**（§13.2） | 单条规则把 `local-asset://cdn.demo.local/pkg/*` 批量映射到沙箱目录 |
| **Handle 生命周期**（§13.3） | `registerHandle` 铸造 capability URI，TTL 到期与显式吊销两条失效路径 |
| **安全模型对比**（§13.4） | 同页对比 Handle capability 与 Registry namespace/scope 两套模型 |
| **错误分类**（§13.5） | 同页触发四类错误，`category + stage` 回传 H5 |
| **Resolver 链覆盖**（§13.6） | 链首自定义 resolver 短路（DYNAMIC，`?mode=` 驱动）+ 链尾目录 resolver（STATIC） |
| **优雅降级**（§13.7） | 有效资源 + 缺失资源 + 已吊销 handle 混合请求，H5 error 事件降级不崩溃 |
| **JSBridge 选图**（§13.8） | `@ohos.file.picker` 原生选图，`previewUri` 往返，Native 反查还原选图记录 |

### 9.1 验收状态（重要）

- **已由自动化测试覆盖**：core 引擎全链路（209 例）、桥接决策逻辑 `SchemeRequestHandler`/`BridgeResponse`/
  目录 resolver（68 例）、sample 的纯逻辑部分——error 探针的四类分类、override banner 的 resolver 匹配与
  DYNAMIC 产出、JSBridge 载荷编解码、文件工具（77 例）。
- **真机人工验收已执行**（HUAWEI FMR0223C13000767，HarmonyOS 5.0，2026-08-05）：§13.1 静态映射、§13.2 目录路由、
  §13.3 句柄生命周期、§13.4 两套安全模型、§13.6 解析器短路覆盖、§13.7 优雅降级共 6 条经设备实测确认渲染与行为正确；
  §13.5 错误分类、§13.8 JSBridge 选图尚未逐条走完（后者需真人选图）。详见 [docs/compatibility.md §13.10](../docs/compatibility.md#1310-当前验收状态)。
- **视觉断言只能由真机验收兑现**：`LocalAssetSchemeHandler` 的 ArkWeb 适配层跑不进 `hvigorw test`（只编译不执行），
  ArkWeb 也没有 Robolectric 等价物，因此「页面结果」「渲染成功/拒绝渲染」「error 事件降级」等断言不在自动化覆盖范围内。

## 10. 与 Android/iOS 的已知差异

### 10.1 不支持 `Stream` 来源与 `AsyncResourceLoader`

harmony 侧不实现 `ResourceSource.Stream` / `ResourceData.Stream` / `AsyncResourceLoader`：
ArkTS 没有与 Android `InputStream`/iOS `InputStream` 对等的可复用惰性流抽象。
`FileResourceLoader` 用 `fs.accessSync` 探测存在性 + `fs.readSync` **同步整读**，
`Bytes`/`FilePath` 即本平台的完整来源集合。

**内存后果**：大文件资源会被一次性完整读入内存，没有分块/流式读取的中间态。
资源体量较大时需要在调用方自行分片或改走其它通道。见 `docs/design.md §9.3`。

### 10.2 ⚠️ 文件根校验无法消解符号链接（安全相关）

| 平台 | 机制 | 能否消解符号链接 |
|------|------|----------------|
| Android | `File(path).canonicalFile.path` | ✅ 能（触碰文件系统） |
| iOS | `URL(fileURLWithPath:).resolvingSymlinksInPath()` | ✅ 能 |
| HarmonyOS | **纯词法规范化**（折叠 `.` / `..`，不碰文件系统） | ❌ 不能 |

`@ohos.file.fs` **没有** realpath/canonical 等价 API（已 grep SDK 的 `.d.ts` 确认）；`lstatSync` 只能判断
某段是否为符号链接，无法解析。

**残留攻击面（harmony 独有）**：若 `/data/app/cache/link` 是指向 `/etc` 的符号链接，
则 `/data/app/cache/link/passwd` 在词法上位于允许根内，**harmony 放行，而 Android/iOS 拒绝**。

> **调用方不应把含有外指符号链接的目录声明为允许根。**

这不是取舍而是平台能力缺失；一旦 ArkTS 提供 realpath API 应立即改用并删除本条。

**另一处方向相反的分叉（更保守，非安全问题）**：Java 的 `canonicalFile` 会把前导 `..` 钳到文件系统根
（`/../data/app/cache/x.png` → `/data/app/cache/x.png` 并接受），harmony 则规范化失败直接拒绝。
该差异在任意允许根下都可能显形，不限于根为 `/` 的情形。harmony 只会比参考实现更严，不会更松。

### 10.3 ⚠️ handle token 熵源：系统 CSPRNG 优先，不可用则 fail-loud

handle token 由 `internal/Uuid.ets` 的 `generateUuidV4()` 生成，采用**优先 CSPRNG、不可用则抛错**的策略：

| 层级 | 熵来源 | 适用环境 | CSPRNG |
|------|--------|---------|--------|
| 1（优先） | `@ohos.security.cryptoFramework.createRandom().generateRandomSync(16)` | 真机 / 模拟器 | ✅ |
| 2（仅测试沙箱显式放行） | `Math.random()` | hvigor 本地单元测试沙箱（需 `allowInsecureRandomFallbackForTests(true)`） | ❌ |

**真机上**：token 使用系统 CSPRNG 生成，与 Kotlin `UUID.randomUUID()`（SecureRandom）
和 iOS `UUID()` 等质量，满足 `docs/design.md §5.4`「token 不可猜测」的要求。CSPRNG 不可用时
**默认抛 `Error`**，绝不静默回退——否则 token 可预测性会让 capability 授权在真机上无声失效。

**沙箱中**：`@ohos.security.cryptoFramework` 的 `generateRandomSync` 静默返回长度为 0 的 `data`
（不抛异常），`Uuid.ets` 检测到长度不为 16 字节即抛错；仅当测试通过显式开关
`allowInsecureRandomFallbackForTests(true)` 放行后才回退 `Math.random()`，保证测试不退化。
回退判据是「返回值长度是否为 16 字节」而非 try-catch——只靠异常捕获会漏过静默退化。

**替换点**：`localasset-core/src/main/ets/internal/Uuid.ets` 是 handle token 熵的唯一入口，
`InMemoryHandleRegistry.register()` 只调用 `generateUuidV4()`。若要修改 token 生成策略，
改这一处即可。

### 10.4 本地单元测试沙箱的系统能力限制

在 DevEco Studio 26.0.0 / SDK API 26 / hypium 1.0.18 下实测：`hvigorw test` 的本地单元测试跑在受限沙箱中，
**部分系统能力静默返回空值而不抛异常**。库内已全部绕开，新增代码同样必须避开：

| API | 沙箱内实测行为 | 库内替代 |
|-----|--------------|---------|
| `util.generateRandomUUID(true)` | 返回**空字符串** | `Uuid.ets` 优先用 `@ohos.security.cryptoFramework` CSPRNG，沙箱经显式开关放行后回退自实现 UUID v4（`internal/Uuid.ets`） |
| `util.TextDecoder.create('utf-8').decodeToString(bytes)` | 返回**空字符串** | `buffer.from(arrayBuffer).toString('utf-8')`（`@ohos.buffer`） |
| `cryptoFramework.createRandom().generateRandomSync(len)` | 返回**长度为 0 的 data** | `Uuid.ets` 检测长度后默认抛错，仅测试沙箱显式放行回退 `Math.random()`，真机正常时使用 CSPRNG |
| `util.TextEncoder` | 同类编解码类不可信 | ASCII 场景逐字符取 `charCodeAt` |

静默返回空值最危险的地方在于**测试里假通过**：用它们生成的 token 会全部退化成同一个空串，
capability 模型直接失效而测试全绿。

**API 签名修正**（与直觉不符，易写错）：

- `fs.accessSync(path)` 返回 **`boolean`**（存在 `true`、缺失 `false`），**不抛异常**。用 try/catch 判存在性是错的。
- `fs.readTextSync` 在该沙箱中**不可调用**（报 `undefined is not callable`），改用 `@ohos.buffer` 解码。

可正常使用（已验证）：tagged union + `kind` 字段类型收窄、`class X extends Error` 与 `instanceof`、
`Map` 的 `forEach`/`entries()`/`delete`/`has`/`size`、字符串正则 `replace`、`Date.now()`、
`fs.statSync`/`openSync`/`readSync`/`closeSync`。

### 10.5 URL 解析：与参考实现的对齐点与已接受的收窄

HarmonyOS 侧手写 URL 解析器（不用 `@ohos.url`，因其边缘行为随 SDK 版本漂移）。已用真实 `java.net.URI`
探针实测对齐：

1. **path 与 fragment 必须百分号解码**，且**顺序为先整串解码、再按 `/` 切段**（decode-then-split）。
   即 `%2F` **确实会**产生段边界：`local-asset://image/a%2Fb` 的 `getPath()` 为 `/a/b`，
   `identifier` 取解码后末段得 `b`（与 Kotlin `URI.getPath()` + `substringAfterLast('/')`、
   Swift `URLComponents.path` 一致）。若改成先切段再逐段解码，`identifier` 会变成 `a/b`，制造出新的三端分叉。
2. **`local-asset://image/`（仅尾斜杠）必须接受**：`path = '/'`、`identifier = null`；
   而 `local-asset://image`（完全无斜杠）仍拒为 `missing path`。
3. **`'+'` 只在 query 中做表单解码**，path 与 fragment 保持字面量（`/a+b/c.png` 就是 `/a+b/c.png`）。
   必须用两个独立解码函数，用同一个会把 `/a+b` 悄悄变成 `/a b`。
4. **非法百分号转义**（如 `%ZZ`）让 `decodeURIComponent` 抛 `URIError`，捕获后转为
   `PARSE_ERROR('invalid url')`，与 Kotlin 的 `URISyntaxException` 对齐。
   已知次要分叉：iOS 的 `URLComponents` 反而容忍 `%ZZ` 并原样返回 path；此处选择与 Android 对齐。

**已接受的收窄**（刻意不对齐，记录备查）：

- namespace 保留 port/userinfo（Kotlin 的 `uri.host` 会剥离）。三端的测试、fixture、sample 中没有任何
  LocalAsset URL 在 namespace 里带 port 或 userinfo，且 `DefaultPolicy` 把 namespace 当不透明令牌。
- query 重复键取最后一个：沿用 Android 语义（既存的 Android/iOS 分叉，不在本次范围内）。
- **合法十六进制但非法 UTF-8 的转义（如 `%FF`、`%C3`）是三端固有分叉，ArkTS 无法同时对齐**：
  Kotlin 接受并产出 U+FFFD；iOS 返回空 path 落到 `missing path`；ArkTS 抛 `URIError` 落到 `invalid url`。
  Android 与 iOS 本就互不一致。三者错误分类**都是 `PARSE_ERROR`**，仅消息不同，且没有 fixture 断言错误消息。
  **后续维护者请勿把 harmony 侧「修」向任一端**——那只会换一个分叉对象。
- 复合非法 URL（同时缺 path 又含非法转义，如 `local-asset://image?q=%ZZ`）：harmony 先校验 namespace/path、
  query 解码延后，故得 `missing path`；实测 iOS 同样得 `missing path`，只有 Kotlin 得 `invalid url`。分类同为 `PARSE_ERROR`。

### 10.6 MIME 推断为手写闭表，与两端有取值分叉

OpenHarmony SDK **没有**扩展名 → MIME 的查询 API：`@ohos.data.uniformTypeDescriptor` 的
`getUniformDataTypeByFilenameExtension` 返回 UTD-ID（形如 `general.plain-text`）而非 MIME 字符串。
Android 用 `MimeTypeMap.getSingleton()`、iOS 用 `UTType(filenameExtension:)`，两者背后都是随系统演进的数据库；
harmony 只能手写一张固定表（`localasset-webview/src/main/ets/mapping/DirectoryResolverSupport.ets`
的 `MIME_BY_EXTENSION`）。

**已知取值分叉**：

| 扩展名 | HarmonyOS | Android | iOS |
|--------|-----------|---------|-----|
| `xml` | `application/xml` | `text/xml` | `text/xml` |
| `js` | `text/javascript` | `application/javascript` | `text/javascript` |
| `ico` | `image/x-icon` | `image/x-icon` | `image/vnd.microsoft.icon` |

`xml` 与 `js` 的分叉不影响字符集行为——两者在 `BridgeResponse.isTextualMime` 下仍判为文本类
（命中 `/xml` 与 `/javascript` 子串），只是 `Content-Type` 字符串不同。

**「闭表」行为更需注意**：表外的任何扩展名一律返回 null → `application/octet-stream`，而 Android/iOS 会给出真实类型。
已知功能性后果：**`wasm` 得不到 `application/wasm`，`WebAssembly.instantiateStreaming` 会直接拒绝**；
`mp3` / `zip` / `wav` / `avif` 同理。需要新扩展名时在 `MIME_BY_EXTENSION` 显式添加。

这是对 `docs/compatibility.md §8.2`「若允许推断，则各端推断策略一致」的**已知偏离**，已在该章记录。
刻意不追平：手写表无法跟踪两个平台各自演进的数据库，「闭表且有文档」优于「开表却悄悄漂移」。

### 10.7 桥接层集成测试依赖真机/模拟器

ArkWeb 没有 Robolectric 等价物，`LocalAssetSchemeHandler` 与真实 `Web` 组件的交互只能通过 sample 人工验收。
决策逻辑（响应该长什么样、状态码、MIME、是否接管）已全部下沉到可单测的 `SchemeRequestHandler` 与 `BridgeResponse`，
适配层只剩机械翻译。**维护约束**：若你要在适配层里写一个「决定响应该是什么」的分支，那条逻辑属于
`SchemeRequestHandler`，写在适配层等于把它挪出测试覆盖范围。

## 11. 设计参考

- [设计文档](../docs/design.md)
- [Web 侧集成指南](../docs/web-integration.md)
- [兼容性规范](../docs/compatibility.md)（HarmonyOS sample 验收范围见 §13）
- [威胁模型](../docs/threat-model.md)
