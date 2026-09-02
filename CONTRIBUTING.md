# Contributing to LocalAsset

本文档面向 LocalAsset 的贡献者与维护者，涵盖开发环境、构建测试、代码风格、提交规范与发布流程。

使用方文档请参考 [README.md](README.md)。

## 目录

1. [开发环境](#1-开发环境)
2. [构建与测试](#2-构建与测试)
   - [2.1 Android](#21-android)
   - [2.2 iOS](#22-ios)
   - [2.3 HarmonyOS](#23-harmonyos)
   - [2.4 全平台一键测试](#24-全平台一键测试)
   - [2.5 测试注意事项](#25-测试注意事项)
3. [代码风格](#3-代码风格)
   - [3.1 Kotlin（Android）](#31-kotlinandroid)
   - [3.2 Swift（iOS）](#32-swiftios)
   - [3.3 ArkTS（HarmonyOS）](#33-arktsharmonyos)
4. [测试规范](#4-测试规范)
5. [提交与 PR](#5-提交与-pr)
6. [发布](#6-发布)
   - [6.1 Android（Maven Central）](#61-androidmaven-central)
   - [6.2 iOS（Swift Package Manager）](#62-iosswift-package-manager)

---

## 1. 开发环境

| 平台 | 工具 | 版本要求 |
|------|------|---------|
| Android | JDK | 21（JVM toolchain 21） |
| Android | Gradle | 使用项目自带 `gradlew` |
| Android | Android SDK | `compileSdk = 35`，`minSdk = 24` |
| iOS | Xcode | Swift 5.9+ |
| HarmonyOS | DevEco Studio | `hvigorw` 位于 `$DEVECO_STUDIO_HOME/tools/hvigor/bin/` |

## 2. 构建与测试

### 2.1 Android

从 `android/` 目录运行：

```bash
./gradlew build                                  # 编译全部模块
./gradlew test                                    # 运行全部测试（core: JVM；webview: Robolectric）
./gradlew :localasset-core:testDebugUnitTest      # 仅 core 测试（快，无需模拟器）
./gradlew :localasset-webview:testDebugUnitTest   # 仅 WebView 桥接测试
./gradlew :sample:testDebugUnitTest               # 示例应用测试
./gradlew :localasset-core:testDebugUnitTest --tests "fully.qualified.TestClass"
```

Core 测试使用 `kotlin.test`，WebView 测试使用 Robolectric 4.14.1。`localasset.repo.root` 系统属性会自动注入用于 fixture 解析。

### 2.2 iOS

从仓库根目录运行：

```bash
cd ios/localasset-core    && swift test
cd ios/localasset-webview && swift test
```

测试框架：Swift Testing / XCTest。

### 2.3 HarmonyOS

从 `harmony/` 目录运行（需要 DevEco Studio）：

```bash
hvigorw test --no-daemon --rerun-tasks   # 全部三个模块
```

> ⚠️ **`hvigorw test` 的退出码不可信**：即使测试用例失败，它也会打印 `BUILD SUCCESSFUL` 并退出 0。`scripts/test.sh` 因此改为解析各模块的 `test_result.txt`，并在运行前删除过期结果文件，防止"什么都没跑"被误判为绿色。详见 `harmony/README.md`。

### 2.4 全平台一键测试

```bash
bash scripts/test.sh   # 运行 Android + iOS + HarmonyOS 测试；必须退出 0
```

**每次代码变更后，所有平台测试必须通过才能视为完成。**

### 2.5 测试注意事项

> ⚠️ **没有 DevEco Studio 时"All tests passed"的含金量会打折。**
>
> `run_harmony()` 在 DevEco Studio 不存在时会**跳过并返回成功**（`scripts/test.sh`）。这是刻意的——没有 HarmonyOS 工具链的贡献者仍应能运行 Android/iOS 套件——跳过会显式打印（`HarmonyOS: SKIPPED (...)`）。但这意味着在这类机器上的一次绿色运行，**包括 CI**，只验证了 Android 和 iOS。修改 `harmony/` 时，请确认输出确实显示 HarmonyOS 执行了，而非仅看最后的 `=== All tests passed ===`。

> ⚠️ **示例应用仅由编译覆盖——且这一覆盖是后来补上的。**
>
> `swift test` 只构建两个 SPM 包，`hvigorw test` 只构建各模块的测试 target；两者都不触碰示例应用。`run_ios()` 和 `run_harmony()` 因此在末尾显式执行 `xcodebuild build` / `assembleHap`；两者都已被确认能让测试变红。（Android 的 `./gradlew test` 已编译示例 `main`，同样方式确认。）
>
> 编译是示例应用获得的**唯一自动化检查**：它们的 UI、JSBridge 接线和引擎组装在任何平台上都没有测试框架。行为回归只能在真机验收（`docs/compatibility.md` §12 / §13）中发现。

## 3. 代码风格

### 3.1 Kotlin（Android）

- `kotlin.code.style=official`。缩进 4 空格。PascalCase 文件/类名；camelCase 函数/属性名。
- `sourceCompatibility = JavaVersion.VERSION_21`，JVM toolchain 21。
- 包名镜像目录结构，位于 `io.github.xesam.android.localasset.{module}.{layer}`（如 `api/`、`model/`、`engine/`、`resolver/`、`policy/`、`loader/`、`internal/`、`error/`）。
- `minSdk = 24`，`compileSdk = 35`，需要 AndroidX。
- 项目包内优先使用 star import；外部依赖使用显式 import。

### 3.2 Swift（iOS）

- Swift 5.9+，Swift Package Manager。缩进 4 空格。PascalCase 类型名；camelCase 函数/属性名。
- `localasset-core` 中禁止 import UIKit/AppKit；`localasset-webview` 中仅可 import WKWebKit。
- `public` API 在命名和语义上与 Android 对齐。

### 3.3 ArkTS（HarmonyOS）

- ArkTS / DevEco Studio + hvigor。缩进 2 空格。PascalCase 类型名；camelCase 函数/属性名。
- `localasset-core` 中禁止 import ArkUI/ArkWeb；`localasset-webview` 中仅可 import `@kit.ArkWeb`。
- 模块位于 `io.github.xesam.harmony.localasset.{core,webview}`；所有公开符号通过各模块的 `Index.ets` barrel 再导出。
- 公开 API 在命名和语义上与 Android/iOS 对齐，除 `harmony/README.md` 中记录的有意差异外（如无 `Stream` source、`resolveUrl`/`resolveRequest` 替代重载）。

## 4. 测试规范

- **框架**：Android 纯 Kotlin 用 `kotlin.test`；Android WebView 用 Robolectric 4.14.1；iOS 用 Swift Testing / XCTest；HarmonyOS 用 hypium。
- **命名**：`{ClassName}Test.kt`（Android）/ `{ClassName}Tests.swift`（iOS）/ `{ClassName}.test.ets`（HarmonyOS），放在对应的测试源根下。
- **HarmonyOS**：每个注册的模块都需要一个 `src/test/List.test.ets` 来注册其测试套件，即使没有用例——未注册的套件会静默不运行。
- **Fixtures**：跨平台共享测试夹具位于 `docs/compatibility-fixtures/`，格式为 JSON。
- **覆盖率**：无强制阈值。聚焦测试引擎流水线（解析、解析、策略校验、加载），因为每个请求都必须经过它。

## 5. 提交与 PR

- **提交信息**：简洁、祈使语气（如 "Add directory routing resolver"）。
- **PR 描述**：概述改了什么、为什么改、影响哪些模块。如果变更涉及跨平台行为，链接到相关设计文档章节（参考 `docs/compatibility.md` 和 fixtures）。
- **跨平台一致性**：修改任一平台的行为时，必须同步检查另外两端。共享 fixture（`docs/compatibility-fixtures/`）是跨平台一致性的约束手段——如果改了行为，更新 fixture 并确认三端测试通过。

## 6. 发布

### 6.1 Android（Maven Central）

Android 库通过 [vanniktech/maven-publish-plugin](https://github.com/vanniktech/gradle-maven-publish-plugin) 发布到 Maven Central Portal。坐标与版本在 `android/gradle.properties`（`GROUP` / `VERSION_NAME`）。

发布凭据可选 —— `./gradlew test` 与 `build` 不依赖凭据，只有 `publishToMavenCentral` 与签名需要：

| 属性 | 用途 |
|------|------|
| `mavenCentralUsername` / `mavenCentralPassword` | Maven Central Portal 账号 |
| `signingKeyId` / `signingKey` / `signingPassword` | GPG 签名（仅当 `signingKey` 存在时才启用签名） |

```bash
cd android
./gradlew :localasset-core:publishToMavenCentral
./gradlew :localasset-webview:publishToMavenCentral
```

### 6.2 iOS（Swift Package Manager）

iOS 包通过 Swift Package Manager 发布（git tag 驱动，无需额外仓库配置）：

```bash
git tag ios/0.0.1 && git push origin ios/0.0.1
```

依赖方使用：

```swift
.package(url: "https://github.com/xesam/local-asset.git", from: "0.0.1")
```
