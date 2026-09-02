# LocalAsset iOS

协议无关的资源解析引擎 iOS 端实现。通过 `WKURLSchemeHandler` 拦截 `local-asset://` 请求，将运行时动态资源安全地提供给 WKWebView。

## 目录

1. [环境要求](#1-环境要求)
2. [模块结构](#2-模块结构)
3. [构建与测试](#3-构建与测试)
4. [快速开始](#4-快速开始)
   - [4.1 构建 LocalAsset 实例](#41-构建-localasset-实例)
   - [4.2 接入 WKWebView](#42-接入-wkwebview)
   - [4.3 在 HTML 中引用资源](#43-在-html-中引用资源)
   - [4.4 运行时注册动态资源](#44-运行时注册动态资源)
   - [4.5 注册 Handle-Backed 动态资源（能力令牌）](#45-注册-handle-backed-动态资源能力令牌)
5. [内置 Resolver](#5-内置-resolver)
6. [生命周期管理](#6-生命周期管理)
7. [失败处理](#7-失败处理)
8. [安全配置](#8-安全配置)
   - [8.1 文件根校验](#81-文件根校验)
   - [8.2 两条注册路径](#82-两条注册路径)
9. [自定义 scheme](#9-自定义-scheme)
   - [9.1 替换 core 端解析与 scheme 注册](#91-替换-core-端解析与-scheme-注册)
   - [9.2 注意事项](#92-注意事项)
10. [示例场景](#10-示例场景)
11. [与 Android 的已知差异](#11-与-android-的已知差异)
12. [发布](#12-发布)
13. [设计参考](#13-设计参考)

---

## 1. 环境要求

- iOS 14+（WKURLSchemeHandler 自定义 scheme 支持）
- Swift 5.9+
- Xcode 15+
- macOS 12+（swift build / swift test 运行环境）
- SPM（Swift Package Manager）

## 2. 模块结构

```text
ios/
├── localasset-core/     # 纯 Swift 引擎（无 UIKit 依赖），支持 iOS 14+ / macOS 12+
├── localasset-webview/  # WKWebView 桥接层（iOS 14+）
└── sample/              # Xcode 示例项目（iOS 16+）
    └── LocalAssetSample.xcodeproj
```

| 模块 | 类型 | 职责 |
|------|------|------|
| `localasset-core` | 纯 Swift 包 | 引擎、模型、resolver、registry、policy、loader。零 UIKit/AppKit 依赖。 |
| `localasset-webview` | Swift 包 | 通过 `WKURLSchemeHandler` 将 `EngineResult` 桥接为 `URLSchemeTask` 响应。依赖 `localasset-core`。 |
| `sample` | Xcode 项目 | 8 个演示场景，覆盖核心能力。 |

## 3. 构建与测试

```bash
# 构建核心引擎
cd ios/localasset-core && swift build

# 运行核心测试（macOS 原生运行，无需模拟器）
cd ios/localasset-core && swift test

# 构建 WebView 桥接层
cd ios/localasset-webview && swift build

# 运行 WebView 桥接层测试
cd ios/localasset-webview && swift test

# 构建示例应用（需要 Xcode）
cd ios/sample && xcodebuild build -project LocalAssetSample.xcodeproj -scheme LocalAssetSample -sdk iphonesimulator
```

> **SPM 依赖**：`localasset-core` 零外部依赖；`localasset-webview` 仅依赖 `localasset-core`。
>
> **测试框架**：Swift Testing + XCTest。测试覆盖引擎流水线全链路（解析、preCheck、postCheck、resolver 短路、loader、错误分类），并通过 `CompatibilityFixtureTests` 加载 `docs/compatibility-fixtures/` 中的共享 JSON 夹具，确保行为与 Android/HarmonyOS 对齐。

## 4. 快速开始

### 4.1 构建 LocalAsset 实例

```swift
import LocalAssetCore

let asset = LocalAsset.Builder()
    .addResolver(
        BundleDirectoryResolver(
            host: "assets.demo.local",
            pathPrefix: "/static",
            bundleDirectory: "demo"
        )
    )
    .build()
```

### 4.2 接入 WKWebView

```swift
import LocalAssetCore
import LocalAssetWebView

let config = WKWebViewConfiguration()
config.setURLSchemeHandler(
    LocalAssetSchemeHandler(engine: asset.engine),
    forURLScheme: "local-asset"
)
let webView = WKWebView(frame: .zero, configuration: config)
```

> **注意**：`local-asset` scheme 必须在 `WKWebView` 创建前注册到 `WKWebViewConfiguration`，之后不可更改。

### 4.3 在 HTML 中引用资源

```html
<link rel="stylesheet" href="local-asset://assets.demo.local/static/styles.css">
<img src="local-asset://assets.demo.local/static/images/logo.svg">
<script src="local-asset://assets.demo.local/static/app.js"></script>
```

未命中任何 resolver 的请求会回退到 WebView 默认加载路径，无需额外处理。

### 4.4 运行时注册动态资源

```swift
let descriptor = ResourceDescriptor(
    id: "dynamic-1",
    namespace: "demo",
    type: .dynamic,
    source: .bytes(imageBytes),
    mimeType: "image/png",
    createdAt: Date(),
    ttlMillis: 60_000 // 1 分钟有效
)
asset.register(descriptor)
// 此时可通过 local-asset://demo/dynamic-1 解析该资源
```

### 4.5 注册 Handle-Backed 动态资源（能力令牌）

```swift
let handle = ResourceHandle(
    bytes: imageData,
    fileName: "photo.jpg",
    mimeType: "image/jpeg",
    ttlMillis: 30_000
)
let uri = asset.registerHandle(handle)
// uri 为 local-asset://handles/<token>/photo.jpg
// 将 uri 传给 H5，H5 通过 <img src="uri"> 即可加载
```

Handle 路径使用不透明 token 保证安全，无需配置 namespace/scope，TTL 到期后自动失效。

## 5. 内置 Resolver

| Resolver | 用途 |
|----------|------|
| `BundleDirectoryResolver` | 将 host + pathPrefix 映射到 App Bundle 资源目录 |
| `FileDirectoryResolver` | 将 host + pathPrefix 映射到文件系统目录 |
| `StaticMapResolver` | 将特定 URL 路径映射到特定文件或字节数据 |
| `RegistryResolver` | 按 ID 查找动态注册的资源（默认位于 resolver 链末尾兜底） |
| `HandleRegistryResolver` | 反向查找 Handle-Backed URI（始终位于 resolver 链首位） |

## 6. 生命周期管理

资源支持显式管理：

```swift
asset.unregister("dynamic-1")   // 移除已注册资源
asset.cleanup()                 // 强制清理过期资源
asset.removeHandle(uri)         // 吊销指定 handle
asset.cleanupHandles()          // 周期性回收过期 handle
```

## 7. 失败处理

未解析的 URL 在 `WKURLSchemeHandler` 中返回 404 响应。所有失败均通过 `EngineObserver`（如已配置）记录错误分类（`PARSE_ERROR`、`RESOLUTION_ERROR`、`LOAD_ERROR`、`SECURITY_ERROR`）及发生的链路阶段。

## 8. 安全配置

### 8.1 文件根校验

默认策略 `DefaultPolicy` 对 `FilePath` 来源**默认 fail-closed**：未配置允许的文件根时，所有文件路径资源都会在 `postCheck` 被拒。要启用文件资源，在 Builder 上声明允许的根目录：

```swift
let asset = LocalAsset.Builder()
    .addAllowedFileRoot(cachesDirectory)   // 允许缓存目录下的文件
    .addAllowedFileRoot(documentsDirectory) // 允许文档目录下的文件
    .build()
```

### 8.2 两条注册路径

| 路径 | 注册方式 | 安全模型 | 适用场景 |
|------|---------|---------|---------|
| **Handle 路径** | `registerHandle(...)` → `local-asset://handles/<token>/<file>` | 能力令牌（token 不可猜测、可吊销、会过期） | 运行时动态资源（相机、临时下载、生成图片） |
| **Registry 路径** | `register(ResourceDescriptor)` | namespace/scope 模型 | 注册时已知归属的描述符 |

## 9. 自定义 scheme

默认 scheme `local-asset` 由 `DefaultLocalAssetSchemeAdapter` 硬编码，Builder 上没有替换 scheme 字面量的配置项；换 scheme 走 `SchemeAdapter` 扩展点。典型动因：宿主内其他组件已占用 `local-asset`，或需要 URI 形态隔离。

### 9.1 替换 core 端解析与 scheme 注册

实现 `SchemeAdapter` 协议并经 `addAdapter(_:)` 注入。一旦注入任何 adapter，默认 adapter 即完全退出解析（Builder 仅在 adapter 列表为空时回落到 `DefaultLocalAssetSchemeAdapter`）：

```swift
struct MyAssetSchemeAdapter: SchemeAdapter {
    func canHandle(url: String) -> Bool {
        URLComponents(string: url)?.scheme == "my-asset"
    }

    func parse(url: String) throws -> AssetRequest {
        // 解析规则参照 DefaultLocalAssetSchemeAdapter——除 scheme 字面量外逐字段保持一致；
        // AssetRequest.scheme 必须填 URL 的真实 scheme（preCheck 与 handle 回溯都依赖它）
        ...
    }
}

let asset = LocalAsset.Builder()
    .addAdapter(MyAssetSchemeAdapter())
    .addResolver(...)
    .build()
```

桥接层**零改动**——`WKURLSchemeHandler` 的 scheme 本来就是注册参数，`LocalAssetSchemeHandler` 自身不持有 scheme。注册时传入新 scheme 即可，时序约束与「4.2 接入 WKWebView」相同（`WKWebView` 创建前注册，之后不可更改）：

```swift
config.setURLSchemeHandler(
    LocalAssetSchemeHandler(engine: asset.engine),
    forURLScheme: "my-asset"
)
```

### 9.2 注意事项

- **`addAllowedScheme(_:)` 不是换 scheme 的开关**：它只是 `DefaultPolicy` preCheck 的 scheme 白名单（默认空 = 放行所有非空 scheme）。配置了该白名单或注入了自定义 `Policy` 时，确认新 scheme 在放行列表内。
- **Handle 路径的 URI 前缀仍为 `local-asset://`**：`InMemoryHandleRegistry` 铸造的 URI 硬编码该前缀（构造参数仅 host、pathPrefix 可配）。要同时使用自定义 scheme 与 `registerHandle()`，需自行实现 `HandleRegistry` 并经 `Builder.handleRegistry(_:)` 注入——`resolveFromRequest` 默认实现按 `request.scheme` 重建 URI，自定义实现铸造与回溯使用同一 scheme 即可闭环。若同时更换 handle host（默认 `defaultHandleHost`），需自建 `DefaultPolicy(handleHost: ...)` 经 `policy(_:)` 注入；Builder 没有该配置项，且注入自定义 `Policy` 后 Builder 的白名单配置全部失效。
- `local-asset` 是三端、H5、共享测试夹具（`docs/compatibility-fixtures/`）与 [Web 侧集成指南](../docs/web-integration.md) 共同固化的跨平台契约；换 scheme 意味着三端与 H5 引用同步迁移，除撞名外不建议更换。

## 10. 示例场景

Sample 应用包含 8 个演示场景，与 `docs/compatibility.md §12`（Android）/`§13`（HarmonyOS）定义的演示流逐条对应——三端逐字节复用 `shared/demo/` 的同一套演示页面：

| 场景 | 说明 |
|------|------|
| **静态映射**（§13.1） | `local-asset://assets.demo.local/static/*` 接管 CSS/JS/图片，同屏一张 `https://` 对照图走内核默认路径 |
| **目录路由**（§13.2） | 单条规则把 `local-asset://cdn.demo.local/pkg/*` 批量映射到 Bundle 资源目录 |
| **Handle 生命周期**（§13.3） | `registerHandle` 铸造 capability URI，TTL 到期与显式吊销两条失效路径 |
| **安全模型对比**（§13.4） | 同页对比 Handle capability 与 Registry namespace/scope 两套模型 |
| **错误分类**（§13.5） | 同页触发四类错误，`category + stage` 回传 H5 |
| **Resolver 链覆盖**（§13.6） | 链首自定义 resolver 短路（DYNAMIC，`?mode=` 驱动）+ 链尾目录 resolver（STATIC） |
| **优雅降级**（§13.7） | 有效资源 + 缺失资源 + 已吊销 handle 混合请求，H5 error 事件降级不崩溃 |
| **JSBridge 选图**（§13.8） | `UIImagePickerController` 原生选图，`local-asset://` URI 往返，Native 反查还原选图记录 |

## 11. 与 Android 的已知差异

iOS 端 core 行为与 Android 完全对齐，以下差异仅在 WebView 桥接层：

| 差异 | 说明 |
|------|------|
| **scheme 注册时机** | iOS 要求在 `WKWebView` 创建前注册 scheme 到 `WKWebViewConfiguration`，且不可更改；Android 的 `shouldInterceptRequest` 可随时挂载 |
| **CORS 处理** | 三端一致：默认不发送 CORS 头，`<img>`/`<link>`/`<script>` 不经 CORS 仍可引用子资源；`fetch()`/`XHR` 需集成方通过 `LocalAssetSchemeHandler(allowedOrigins:…)` 显式放行（命中回显 origin + `Vary: Origin`，含 `"*"` 恢复通配）。iOS 的 `WKURLSchemeHandler` 对自定义 scheme 默认不发送 CORS 预检，`LocalAssetSchemeHandler` 按上述规则设置响应头 |
| **错误响应** | iOS 无法返回"未拦截"信号（scheme handler 必须完成 task），未命中的请求返回 404；Android 的 `shouldInterceptRequest` 返回 `null` 时 WebView 自动回退 |

## 12. 发布

iOS 包通过 Swift Package Manager 发布（git tag 驱动）：

```bash
git tag ios/0.0.1 && git push origin ios/0.0.1
# 依赖方：.package(url: "https://github.com/xesam/local-asset.git", from: "0.0.1")
```

## 13. 设计参考

完整架构、设计原则与跨平台规范参见：
- [设计文档](../docs/design.md)
- [Web 侧集成指南](../docs/web-integration.md)
- [兼容性规范](../docs/compatibility.md)
- [威胁模型](../docs/threat-model.md)
