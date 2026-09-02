# LocalAsset Android

协议无关的资源解析引擎 Android 端实现。Maven 坐标：`io.github.xesam.android.localasset`。

## 目录

1. [环境要求](#1-环境要求)
2. [模块说明](#2-模块说明)
3. [构建](#3-构建)
   - [3.1 运行测试](#31-运行测试)
   - [3.2 运行示例应用](#32-运行示例应用)
4. [快速开始](#4-快速开始)
   - [4.1 构建 LocalAsset 实例](#41-构建-localasset-实例)
   - [4.2 接入 WebView](#42-接入-webview)
   - [4.3 在 HTML 中引用资源](#43-在-html-中引用资源)
   - [4.4 运行时注册动态资源](#44-运行时注册动态资源)
5. [内置 Resolver](#5-内置-resolver)
6. [生命周期管理](#6-生命周期管理)
7. [失败处理](#7-失败处理)
8. [自定义 scheme](#8-自定义-scheme)
   - [8.1 替换 core 端解析](#81-替换-core-端解析)
   - [8.2 注意事项](#82-注意事项)
9. [示例场景](#9-示例场景)
10. [设计参考](#10-设计参考)

---

## 1. 环境要求

- Android SDK 24+（minSdk 24）
- Kotlin 2.0+
- JDK 21

## 2. 模块说明

| 模块 | 类型 | 职责 |
|------|------|------|
| `localasset-core` | 纯 Kotlin 库 | 引擎、模型、resolver、registry、policy、loader。零 Android 框架依赖。 |
| `localasset-webview` | Android 库 | 通过 `shouldInterceptRequest` 将 `EngineResult` 桥接为 `WebResourceResponse`。依赖 `localasset-core`。 |
| `sample` | 示例应用 | 8 个演示场景，覆盖核心能力。 |

## 3. 构建

```bash
cd android
./gradlew build
```

### 3.1 运行测试

```bash
# 所有模块
./gradlew test

# 单个模块
./gradlew :localasset-core:testDebugUnitTest
./gradlew :localasset-webview:testDebugUnitTest

# 单个测试类
./gradlew :localasset-core:testDebugUnitTest --tests "io.github.xesam.android.localasset.core.engine.DefaultLocalAssetEngineTest"
```

### 3.2 运行示例应用

```bash
./gradlew :sample:assembleDebug
./gradlew :sample:installDebug
```

## 4. 快速开始

### 4.1 构建 LocalAsset 实例

```kotlin
val localAsset = LocalAsset.Builder()
    .addResolver(
        AssetDirectoryResolver(
            appContext = context,
            host = "assets.demo.local",
            pathPrefix = "/static",
            assetDirectory = "sample/static",
        ),
    )
    .build()
```

### 4.2 接入 WebView

```kotlin
webView.webViewClient = LocalAssetWebViewClient(
    interceptor = WebViewAssetInterceptor(
        engine = localAsset.engine,
        responseBuilder = DefaultWebViewResponseBuilder(),
        contextFactory = AndroidResolveContextFactory(engineScope = "my-engine"),
    ),
)
```

### 4.3 在 HTML 中引用资源

```html
<link rel="stylesheet" href="local-asset://assets.demo.local/static/styles.css">
<img src="local-asset://assets.demo.local/static/images/logo.svg">
<script src="local-asset://assets.demo.local/static/app.js"></script>
```

未命中任何 resolver 的请求会回退到 WebView 默认加载路径，无需额外处理。

### 4.4 运行时注册动态资源

```kotlin
val descriptor = ResourceDescriptor(
    id = "dynamic-1",
    namespace = "demo",
    type = ResourceType.DYNAMIC,
    source = BytesSource(imageBytes),
    mimeType = "image/png",
    createdAtMillis = System.currentTimeMillis(),
    ttlMillis = 60_000, // 1 分钟有效
)
localAsset.register(descriptor)
// 此时可通过 local-asset://demo/dynamic-1 解析该资源
```

## 5. 内置 Resolver

| Resolver | 用途 |
|----------|------|
| `AssetDirectoryResolver` | 将 host + pathPrefix 映射到 Android assets 目录 |
| `FileDirectoryResolver` | 将 host + pathPrefix 映射到文件系统目录 |
| `StaticMapResolver` | 将特定 URL 路径映射到特定文件或字节数据 |
| `RegistryResolver` | 按 ID 查找动态注册的资源（默认位于 resolver 链末尾兜底） |
| `HandleRegistryResolver` | 反向查找 Handle-Backed URI（始终位于 resolver 链首位） |

## 6. 生命周期管理

资源支持显式管理：

```kotlin
localAsset.unregister("dynamic-1")   // 移除已注册资源
localAsset.cleanup()                 // 强制清理过期资源
```

## 7. 失败处理

未解析的 URL 在 `shouldInterceptRequest` 中返回 `null`，WebView 回退到默认加载行为。所有失败均通过日志记录错误分类（`PARSE_ERROR`、`RESOLUTION_ERROR`、`LOAD_ERROR`、`SECURITY_ERROR`）及发生的链路阶段。

## 8. 自定义 scheme

默认 scheme `local-asset` 由 `DefaultLocalAssetSchemeAdapter` 硬编码，Builder 上没有替换 scheme 字面量的配置项；换 scheme 走 `SchemeAdapter` 扩展点。典型动因：宿主内其他组件已占用 `local-asset`，或多库共用同一 WebView 时需要 URI 形态隔离。

### 8.1 替换 core 端解析

实现 `SchemeAdapter` 并经 `addAdapter()` 注入。一旦注入任何 adapter，默认 adapter 即完全退出解析（Builder 仅在 adapter 列表为空时回落到 `DefaultLocalAssetSchemeAdapter`）：

```kotlin
class MyAssetSchemeAdapter : SchemeAdapter {
    override fun canHandle(url: String): Boolean = runCatching {
        URI(url).scheme == "my-asset"
    }.getOrDefault(false)

    override fun parse(url: String): AssetRequest {
        // 解析规则参照 DefaultLocalAssetSchemeAdapter——除 scheme 字面量外逐字段保持一致；
        // AssetRequest.scheme 必须填 URL 的真实 scheme（preCheck 与 handle 回溯都依赖它）
        ...
    }
}

val localAsset = LocalAsset.Builder()
    .addAdapter(MyAssetSchemeAdapter())
    .addResolver(...)
    .build()
```

WebView 桥接层**零改动**：`LocalAssetWebViewClient` 不做 scheme 过滤，所有请求交给引擎，由 adapter 链的 `canHandle` 决定归属——`my-asset://` 请求自动进入同一套 preCheck → resolver 链 → postCheck 管线，失败语义（见「失败处理」）不变。

### 8.2 注意事项

- **`addAllowedScheme()` 不是换 scheme 的开关**：它只是 `DefaultPolicy` preCheck 的 scheme 白名单（默认空 = 放行所有非空 scheme）。配置了该白名单或注入了自定义 `Policy` 时，确认新 scheme 在放行列表内。
- **Handle 路径的 URI 前缀仍为 `local-asset://`**：`InMemoryHandleRegistry` 铸造的 URI 硬编码该前缀（构造参数仅 host、pathPrefix 可配）。要同时使用自定义 scheme 与 `registerHandle()`，需自行实现 `HandleRegistry` 并经 `Builder.handleRegistry()` 注入——`resolveFromRequest` 默认实现按 `request.scheme` 重建 URI，自定义实现铸造与回溯使用同一 scheme 即可闭环。若同时更换 handle host（默认 `HandleRegistry.DEFAULT_HANDLE_HOST`），需自建 `DefaultPolicy(handleHost = ...)` 经 `policy()` 注入；Builder 没有该配置项，且注入自定义 `Policy` 后 Builder 的白名单配置全部失效。
- `local-asset` 是三端、H5、共享测试夹具（`docs/compatibility-fixtures/`）与 [Web 侧集成指南](../docs/web-integration.md) 共同固化的跨平台契约；换 scheme 意味着三端与 H5 引用同步迁移，除撞名外不建议更换。

## 9. 示例场景

Sample 应用包含 8 个演示场景，逐条对应 `docs/compatibility.md §12`：

| 场景 | 说明 |
|------|------|
| **静态映射**（§12.1） | 通过 `local-asset://assets.demo.local/static/*` 加载 CSS、JS、图片子资源，同屏一张 `https://` 对照图按 WebView 默认路径加载，验证默认加载路径未被库接管 |
| **目录路由**（§12.2） | 单条规则把 `local-asset://cdn.demo.local/pkg/*` 批量映射到文件系统目录 |
| **Handle 生命周期**（§12.3） | `registerHandle` 铸造 capability URI，TTL 到期与显式吊销两条失效路径 |
| **安全模型对比**（§12.4） | 同页对比 Handle capability 与 Registry namespace/scope 两套模型 |
| **错误分类**（§12.5） | 同页触发四类错误，`category + stage` 回传 H5 |
| **Resolver 链覆盖**（§12.6） | 链首自定义 resolver 短路（DYNAMIC，`?mode=` 驱动）+ 链尾目录 resolver（STATIC） |
| **优雅降级**（§12.7） | 有效资源 + 刻意缺失资源 + 已吊销 handle 混合请求，H5 error 事件降级，页面稳定不崩溃 |
| **JSBridge 选图**（§12.8） | Web 通过 JSBridge 触发原生选图；选中的图片通过可逆的 `local-asset://` URI 预览；提交时将 URI 回传 Native 还原选图记录 |

## 10. 设计参考

完整架构、设计原则与跨平台规范参见：
- [设计文档](../docs/design.md)
- [Web 侧集成指南](../docs/web-integration.md)
- [兼容性规范](../docs/compatibility.md)
- [威胁模型](../docs/threat-model.md)
