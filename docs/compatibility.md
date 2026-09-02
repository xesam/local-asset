# LocalAsset 跨平台兼容性规范

## 目录

1. [目标](#1-目标)
2. [URL 解析一致性](#2-url-解析一致性)
   - [用例 2.1 基础 URL 解析](#用例-21-基础-url-解析)
   - [用例 2.2 非法 URL](#用例-22-非法-url)
3. [Resolver 顺序与短路](#3-resolver-顺序与短路)
   - [用例 3.1 首个命中短路](#用例-31-首个命中短路)
   - [用例 3.2 跳过后继续](#用例-32-跳过后继续)
   - [用例 3.3 Resolver 失败](#用例-33-resolver-失败)
4. [Registry 行为](#4-registry-行为)
   - [用例 4.1 注册后可解析](#用例-41-注册后可解析)
   - [用例 4.2 资源移除](#用例-42-资源移除)
   - [用例 4.3 重复注册](#用例-43-重复注册)
5. [TTL 与过期](#5-ttl-与过期)
   - [用例 5.1 TTL 生效](#用例-51-ttl-生效)
   - [用例 5.2 惰性清理](#用例-52-惰性清理)
6. [Scope 隔离](#6-scope-隔离)
   - [用例 6.1 Engine Scope 隔离](#用例-61-engine-scope-隔离)
   - [用例 6.2 Page Scope 隔离](#用例-62-page-scope-隔离)
7. [Policy 行为](#7-policy-行为)
   - [用例 7.1 Pre-Check 拒绝](#用例-71-pre-check-拒绝)
   - [用例 7.2 Post-Check 拒绝](#用例-72-post-check-拒绝)
   - [用例 7.3 文件根包含判定](#用例-73-文件根包含判定)
8. [Loader 与响应构建](#8-loader-与响应构建)
   - [用例 8.1 Source 不可读](#用例-81-source-不可读)
   - [用例 8.2 MIME 信息缺失](#用例-82-mime-信息缺失)
9. [错误映射](#9-错误映射)
   - [用例 9.1 Not Found](#用例-91-not-found)
   - [用例 9.2 Forbidden](#用例-92-forbidden)
10. [可观测性](#10-可观测性)
    - [用例 10.1 Trace 最小信息](#用例-101-trace-最小信息)
11. [验收方式](#11-验收方式)
12. [Android Sample Flows](#12-android-sample-flows)
    - [用例 12.1 Static Mapping Flow](#用例-121-static-mapping-flow)
    - [用例 12.2 Directory Routing Flow](#用例-122-directory-routing-flow)
    - [用例 12.3 Handle Lifecycle Flow](#用例-123-handle-lifecycle-flow)
    - [用例 12.4 Security Models Flow](#用例-124-security-models-flow)
    - [用例 12.5 Error Categories Flow](#用例-125-error-categories-flow)
    - [用例 12.6 Resolver Chain Override Flow](#用例-126-resolver-chain-override-flow)
    - [用例 12.7 Graceful Degradation Flow](#用例-127-graceful-degradation-flow)
    - [用例 12.8 JSBridge Image Picker Flow](#用例-128-jsbridge-image-picker-flow)
    - [12.9 Fixture 对齐要求](#129-fixture-对齐要求)
13. [HarmonyOS Sample Flows](#13-harmonyos-sample-flows)
    - [用例 13.1 Static Mapping Flow](#用例-131-static-mapping-flow)
    - [用例 13.2 Directory Routing Flow](#用例-132-directory-routing-flow)
    - [用例 13.3 Handle Lifecycle Flow](#用例-133-handle-lifecycle-flow)
    - [用例 13.4 Security Models Flow](#用例-134-security-models-flow)
    - [用例 13.5 Error Categories Flow](#用例-135-error-categories-flow)
    - [用例 13.6 Resolver Chain Override Flow](#用例-136-resolver-chain-override-flow)
    - [用例 13.7 Graceful Degradation Flow](#用例-137-graceful-degradation-flow)
    - [用例 13.8 JSBridge Image Picker Flow](#用例-138-jsbridge-image-picker-flow)
    - [13.9 Fixture 对齐要求](#139-fixture-对齐要求)
    - [13.10 当前验收状态](#1310-当前验收状态)

---

## 1. 目标

本规范用于约束 Android、iOS 与 HarmonyOS 在 LocalAsset SDK 上的产品行为保持一致。

验证原则：

- 同一输入应得到同一语义输出
- 同一错误场景应落入同一错误分类
- 平台允许实现差异，不允许行为语义分叉

平台专属的偏离必须在本文件中显式登记。当前已登记项：

| 位置 | 偏离 | 方向 |
|------|------|------|
| §7.3 | HarmonyOS 文件根校验无法消解符号链接（`@ohos.file.fs` 无 realpath API） | HarmonyOS 更宽松（安全相关） |
| §7.3 | HarmonyOS 拒绝前导 `..`，而 Java/iOS 钳到文件系统根后接受 | HarmonyOS 更保守 |
| §8.2 | HarmonyOS 的 MIME 推断为手写闭表，与两端有取值分叉且表外落 `application/octet-stream` | 取值分叉 + 覆盖面收窄 |

## 2. URL 解析一致性

### 用例 2.1 基础 URL 解析

输入：

```text
local-asset://image/logo?id=home&theme=dark
```

期望：

- `scheme = local-asset`
- `namespace = image`
- `identifier = logo` 或按约定映射出的稳定标识
- `query.id = home`
- `query.theme = dark`

### 用例 2.2 非法 URL

输入：

```text
local-asset:///invalid
```

期望：

- 进入 `parse_error`
- 不进入 resolver 链

## 3. Resolver 顺序与短路

### 用例 3.1 首个命中短路

前置条件：

- 注册 `ResolverA`
- 注册 `ResolverB`
- 两者都能命中同一请求

期望：

- 只返回 `ResolverA` 的结果
- `ResolverB` 不应继续执行为有效命中

### 用例 3.2 跳过后继续

前置条件：

- `ResolverA` 返回跳过
- `ResolverB` 命中

期望：

- 返回 `ResolverB` 的结果
- 错误分类不应产生

### 用例 3.3 Resolver 失败

前置条件：

- `ResolverA` 在解析过程中抛出内部错误

期望：

- 进入 `resolution_error`
- 错误不能被默默视为“跳过”

## 4. Registry 行为

### 用例 4.1 注册后可解析

前置条件：

- 注册一个 `id = asset-1` 的 descriptor

期望：

- 在 TTL 有效期内可以被解析成功

### 用例 4.2 资源移除

前置条件：

- 注册 `asset-1`
- 执行 remove

期望：

- 后续请求不能再命中该资源
- 结果应进入 `resolution_error`，具体子类可为 not found

### 用例 4.3 重复注册

前置条件：

- 已存在 `asset-1`
- 再次注册 `asset-1`

期望：

- 行为必须与规格一致
- 若默认不允许覆盖，则返回冲突错误

## 5. TTL 与过期

### 用例 5.1 TTL 生效

前置条件：

- 注册 TTL 为 1 秒的资源
- 超过 1 秒后访问

期望：

- 资源不可继续解析
- 内部错误类别为 `resolution_error`
- 子类应为 `resource expired`

### 用例 5.2 惰性清理

前置条件：

- 资源已过期，但 cleanup 尚未执行

期望：

- 访问结果仍应视为过期
- 不允许因为尚未物理删除而继续读取

## 6. Scope 隔离

### 用例 6.1 Engine Scope 隔离

前置条件：

- 在 `EngineA` 注册资源
- 用 `EngineB` 访问

期望：

- 默认不可访问
- 进入 `security_error` 或按宿主映射策略降级，但内部分类必须一致

### 用例 6.2 Page Scope 隔离

前置条件：

- 在 `PageA` 创建 page-scoped 资源
- 在 `PageB` 访问

期望：

- 访问被拒绝
- 内部错误类别为 `security_error`

## 7. Policy 行为

### 用例 7.1 Pre-Check 拒绝

前置条件：

- namespace 不合法

期望：

- 请求在 resolver 执行前被拒绝
- 进入 `security_error` 或 `parse_error`，具体以规格定义为准，但双端必须一致

### 用例 7.2 Post-Check 拒绝

前置条件：

- resolver 已命中 descriptor
- descriptor 的 source type 被 policy 禁止

期望：

- 请求被拒绝
- 不进入实际 loader 读取
- 错误类别为 `security_error`

### 用例 7.3 文件根包含判定

前置条件：

- resolver 已命中一个 `FilePath` 来源的 descriptor
- 通过 `addAllowedFileRoot` 声明了允许根

期望：

- 落在允许根内的路径放行，根外的路径拒绝，错误类别为 `security_error`
- 比对前必须先规范化路径（折叠 `.` / `..`），且比对必须带分隔符——否则兄弟目录
  `/data/app/cache-evil` 会被误判为 `/data/app/cache` 之下
- 规范化失败一律 fail-closed
- **`descriptor.source.value` 从不经过 preCheck**（preCheck 的 `..` 段拦截只作用于
  `request.path` / `request.identifier`），因此文件根校验是该值唯一的安全闸门

**已登记偏离：HarmonyOS 无法消解符号链接**

三端的包含判定机制不同：

| 平台 | 机制 | 能否消解符号链接 |
|------|------|----------------|
| Android | `File(path).canonicalFile.path` | ✅ 能（触碰文件系统） |
| iOS | `URL(fileURLWithPath:).resolvingSymlinksInPath()` | ✅ 能 |
| HarmonyOS | **纯词法规范化**（折叠 `.` / `..`，不碰文件系统） | ❌ 不能 |

原因：`@ohos.file.fs` 没有 realpath/canonical 等价 API（已 grep SDK 的 `.d.ts` 确认）；
`lstatSync` 只能判断某段是否为符号链接，无法解析。这**不是取舍而是平台能力缺失**。

由此产生两处方向相反的分叉，均为 §1「不允许行为语义分叉」的已登记例外：

**1. 符号链接逃逸 —— HarmonyOS 更宽松（安全相关，真实缺口）**

若 `/data/app/cache/link` 是指向 `/etc` 的符号链接，则 `/data/app/cache/link/passwd`
在词法上位于允许根内：**HarmonyOS 放行，而 Android/iOS 拒绝**。同一输入得到不同结果。

> **调用方约束：不应把含有外指符号链接的目录声明为允许根。**

一旦 ArkTS 提供 realpath API 应立即改用并删除本条。

**2. 前导 `..` —— HarmonyOS 更保守（无安全风险，但方向易被误"修"）**

Java 的 `canonicalFile` 按 POSIX 语义把越过文件系统根的 `..` **钳**在根上
（实测 `/../data/app/cache/x.png` → `/data/app/cache/x.png` 并接受），iOS 的
`resolvingSymlinksInPath` 同理；HarmonyOS 规范化直接返回 null 并拒绝。

该分歧**不限于根为 `/` 的情形**：只要路径带前导 `..` 且折叠后仍落在某个允许根内就会显形。
方向上 HarmonyOS 只会多拒、绝不多放，因此不构成安全分歧，只是可用性上更严格。
**维护者请勿把它"对齐"成钳到根**——那会削弱一道刻意收紧的闸门。

细节见 `harmony/README.md`「⚠️ 文件根校验无法消解符号链接（安全相关）」。

## 8. Loader 与响应构建

### 用例 8.1 Source 不可读

前置条件：

- descriptor 指向不可读取 source

期望：

- 错误类别为 `load_error`

### 用例 8.2 MIME 信息缺失

前置条件：

- descriptor 未提供 mimeType

期望：

- 若允许推断，则各端推断策略一致
- 若不允许推断，则进入统一 `load_error` 或定义好的子类

**已登记偏离：HarmonyOS 的 MIME 推断为手写闭表**

OpenHarmony SDK 没有扩展名 → MIME 的查询 API（`@ohos.data.uniformTypeDescriptor` 只返回 UTD-ID，
形如 `general.plain-text`，不是 MIME 字符串），而 Android 用 `MimeTypeMap`、iOS 用 `UTType`，
两者背后都是随系统演进的数据库。HarmonyOS 只能维护一张固定表，因此**不满足本条的「各端推断策略一致」**：

| 扩展名 | HarmonyOS | Android | iOS |
|--------|-----------|---------|-----|
| `xml` | `application/xml` | `text/xml` | `text/xml` |
| `js` | `text/javascript` | `application/javascript` | `text/javascript` |
| `ico` | `image/x-icon` | `image/x-icon` | `image/vnd.microsoft.icon` |

`xml`/`js` 的分叉只影响 `Content-Type` 字符串，不影响字符集判定（两者仍判为文本类）。

**闭表后果更需注意**：表外扩展名一律落到 `application/octet-stream`，而 Android/iOS 会给出真实类型。
已知功能性后果：`wasm` 得不到 `application/wasm`，`WebAssembly.instantiateStreaming` 会直接拒绝；
`mp3`/`zip`/`wav`/`avif` 同理。需要新扩展名时须在 HarmonyOS 的 `MIME_BY_EXTENSION` 显式添加。

刻意不追平：手写表无法跟踪两个平台各自演进的数据库，「闭表且有文档」优于「开表却悄悄漂移」。
细节见 `harmony/README.md`「MIME 推断为手写闭表」。

## 9. 错误映射

### 用例 9.1 Not Found

前置条件：

- 没有任何 resolver 命中

期望：

- 内部分类为 `resolution_error`
- 对外可映射为 not found

### 用例 9.2 Forbidden

前置条件：

- 资源存在但被 policy 拒绝

期望：

- 内部分类为 `security_error`
- 不允许在某平台被误归类为普通未命中

## 10. 可观测性

### 用例 10.1 Trace 最小信息

每次请求至少应能在内部日志中定位：

- adapter 命中情况
- resolver 执行顺序
- policy 拒绝点
- descriptor id 或关键标识
- 错误阶段与错误类别

## 11. 验收方式

建议将本清单转换为两层测试资产：

1. 平台无关的行为用例表
2. Android、iOS 与 HarmonyOS 各自的自动化测试实现

建议至少维护以下 fixture 分层：

- `docs/compatibility-fixtures/basic-routing.json`
  - 承载跨平台共享的 URL 解析与基础路由输入输出
- `docs/compatibility-fixtures/android-sample-flows.json`
  - 承载 Android sample 必须覆盖的演示流
- `docs/compatibility-fixtures/harmony-sample-flows.json`
  - 承载 HarmonyOS sample 必须覆盖的演示流，与 Android 的那份平行但独立维护

fixture 维护规则：

- 影响跨平台行为的一般性输入输出，优先进入共享 fixture
- 只影响某一端 sample 演示覆盖面的输入输出，进入该端的 sample fixture
- fixture 只描述输入、前置条件摘要和预期语义，不描述平台实现类名

验收标准：

- 所有必选用例在 Android、iOS 和 HarmonyOS 上均通过
- 任一平台新增行为时，必须先更新本清单，再更新实现

## 12. Android Sample Flows

本章约束 Android `sample` 模块必须覆盖的演示流，确保示例工程不是脱离规格的独立 demo。

> **演示入口与承载方式（三端共用，§12/§13 均适用）**
>
> 演示内容**只有一份**，存放在 `shared/demo/`，三端逐字节复用，仓库中不存在第二份副本：
> Android 经 Gradle `assets.srcDirs` 挂载，iOS 经 Xcode folder reference，HarmonyOS 因 rawfile
> 无挂载机制而由 `scripts/sync-harmony-demo.sh` 物理同步（产物 gitignore，构建钩子自动执行）。
>
> **首页与页间跳转同样由共享 HTML 承担**（`shared/demo/pages/index.html` 里的 `<a href>`），
> 不是原生列表页。本条款是对「每个 flow 都必须有对应演示入口」的落实方式说明 ——
> 入口为共享 HTML 页面即满足 §12.9 / §13.9，规格不要求入口是原生实现。
>
> 由此，三端原生侧各自只剩**一个** WebView 容器（`DemoActivity` / `DemoViewController` /
> `pages/Index.ets`），只负责装载 WebView、构建引擎、实现 JSBridge；演示的标题、说明、
> 分组、按钮一律不得写在原生侧。**8 条 flow 因此共用同一个引擎实例**（各场景 host 互不
> 重叠，handleRegistry 合一后行为不变），各端的合并依据记录在 `DemoEngine` 的类注释里。


### 用例 12.1 Static Mapping Flow

要求：

- WebView 页面应先加载普通 shell HTML，再通过 `local-asset://assets.demo.local/static/*` 请求静态子资源
- Android sample 必须展示 CSS、脚本和图片等子资源命中成功后的页面结果
- Android sample 必须在同一页面中同时展示两张同类图片资源：一张通过 `local-asset://` 命中并被库接管，另一张不被库接管并按 WebView 默认资源加载路径正常显示
- 不被库接管的那张对照图片可直接使用外部 `https://` 图片资源，但验收重点是“默认加载路径未被库接管”，而不是协议本身
- 静态资源映射应通过正式规则映射 API 接入，而不是 sample 私有 resolver 逻辑

### 用例 12.2 Directory Routing Flow

要求：

- Android sample 必须展示 `host + path prefix -> 私有目录` 的批量静态资源映射
- 页面中应有一组来自同一路径规则的 CSS、脚本和图片资源
- 规则映射必须复用正式 builder + 正式映射类型，而不是 sample 私有分支逻辑

### 用例 12.3 Handle Lifecycle Flow

要求：

- Android sample 必须展示 `registerHandle` 返回的 `local-asset://<host>/handles/<token>/<file>` capability URI：不可猜测、可吊销、会过期
- 页面必须显式展示该 URI，并以 `<img>` 渲染其承载的资源
- 必须提供"TTL 到期"与"显式吊销"两条路径，并在之后对同一 URI 再次访问，验证其不再解析为 `RESOLUTION_ERROR`（stage `resolve`）
- 必须提供原生 `resolveHandle` 探测入口，把成功/失败（category + stage）回传 H5 可见
- 句柄反查/吊销/过期必须复用正式 `HandleRegistry` 能力，而非 sample 私有 store

### 用例 12.4 Security Models Flow

要求：

- Android sample 必须在同一页面对比两条注册路径的访问控制模型（参见 `docs/design.md §5.4`）：
  - Handle 路径（capability）：`registerHandle` 注册，`scope = null`，不受作用域约束，任意上下文可解析
  - Registry 路径（namespace/scope）：`ResourceDescriptor` 以 `scope = ENGINE` 注册，仅当 `descriptor.namespace == context.engineScope` 时通过，否则 `SECURITY_ERROR`（stage `policy_post`）
- 必须同时展示"namespace 匹配"（渲染成功）与"namespace 不匹配"（拒绝渲染）两种 Registry 结果
- 必须提供原生 `engine.resolve` 探测入口，对不匹配 URL 返回 `SECURITY_ERROR / policy_post`，使错误类别在 H5 可见
- 上下文 `engineScope` 必须通过正式 webview 桥接（`LocalAssetWebViewClient` 的 `engineScope` 入参）注入，而非 sample 私有 hack

### 用例 12.5 Error Categories Flow

要求：

- Android sample 必须在同一页面触发四类错误，并通过原生 `engine.resolve` 捕获 `ResourceException`，把 `category + stage` 回传 H5 展示：
  - `PARSE_ERROR`（stage `adapter_parse`）—— 非法 URL（如 `local-asset://`，无 host）
  - `RESOLUTION_ERROR`（stage `resolve`）—— 无 resolver 命中
  - `LOAD_ERROR`（stage `load`）—— `FilePath` 源在允许根下但缺失（postCheck 通过后由 loader 拒绝）
  - `SECURITY_ERROR`（stage `policy_post`）—— Registry ENGINE scope 下 `namespace != engineScope`
- 四类错误必须复用正式 `EngineResult.Failure` 的 category + stage，而非 sample 自造分类
- 上下文 `engineScope` 与允许文件根必须通过正式 builder 配置注入

### 用例 12.6 Resolver Chain Override Flow

要求：

- Android sample 必须展示 resolver 链路短路（参见 `docs/design.md §3.4`）：链首的自定义 `ResourceResolver` 对特定路径返回 `Hit` 即终止，其余路径返回 `Skip` 落到链尾的基础目录 resolver
- 必须在同一命名空间下展示"被覆盖路径"（由自定义 resolver 命中，DYNAMIC，`?mode=` 驱动）与"基础路径"（由目录 resolver 命中，STATIC）两种结果
- 自定义 resolver 与目录 resolver 必须复用正式 `addResolver` + 正式映射类型，而非 sample 私有分支
- `?mode=` 驱动的动态解析必须体现 DYNAMIC 资源类型

### 用例 12.7 Graceful Degradation Flow

要求：

- Android sample 必须展示 H5 侧的优雅降级：页面同时请求多条 `local-asset://` 子资源，其中包含有效资源、刻意缺失的静态资源、以及一条已吊销的 handle URI
- 已吊销 handle URI 必须通过正式 `registerHandle` + `removeHandle` 产生，而非 sample 私有不可解析 URI
- 缺失与吊销资源必须通过 H5 error 事件降级，页面保持稳定不崩溃
- 有效资源必须正常加载，与降级资源形成对照

### 用例 12.8 JSBridge Image Picker Flow

要求：

- Android sample 必须展示 Web 通过 JSBridge 发起原生选图
- 选中的图片预览必须通过可解析、可反查的 `previewUri` 返回给 WebView；URI 的内部编码格式属于实现细节，不作为产品契约的一部分
- Web 点击提交时必须回传 `previewUri`，而不是 token
- Native 在提交阶段必须先解析 `previewUri`，并根据解析结果还原选图记录
- 这项“由资源 URI 反查 Native 资源句柄”的能力应由正式库能力提供，而不是长期依赖 sample 私有 store/codec 维持
- 推荐由独立的 `HandleRegistry` 或平台等价正式能力承担这项职责，而不是把句柄反查硬塞进普通 `ResourceRegistry`
- Android sample 当前通过 `metadata["android.content_uri"]` 从 handle 记录中取回原始来源；该 key 属于 Android 宿主约定，不属于跨平台正式契约
- 提交后，sample 必须展示 Native 还原后的业务可用结果：
  `contentUri`、`localCachePath`、`fileName`、`mimeType`、`size`
- `localCachePath` 应表示 Native 基于原始选图记录生成的业务可用落地文件，而不是仅返回预览缓存路径
- JSBridge 页不得引入 SDK 正式公开面的 demo 专用 API

### 12.9 Fixture 对齐要求

要求：

- `android-sample-flows.json` 中定义的每个 sample flow 都必须在 sample 中有对应演示入口
- sample 演示流名称、输入 URL 与预期语义必须与 fixture 保持一致
- 若 sample 新增演示页面且会进入正式验收范围，必须先更新此处用例和对应 fixture

## 13. HarmonyOS Sample Flows

本章约束 HarmonyOS `sample` 模块必须覆盖的演示流，与 §12（Android）平行且各自独立。
HarmonyOS 侧不实现 `Stream` 来源（见 `docs/design.md §9.3`），涉及 Stream 的断言不适用于本章。

平台专有名词对应关系：Android 的 `assets/` → HarmonyOS 的 `resources/rawfile/`；
`shouldInterceptRequest` → `WebSchemeHandler`（`LocalAssetSchemeHandler`）；Activity → ArkUI 页面（`@Entry @Component`）。

### 用例 13.1 Static Mapping Flow

要求：

- ArkUI 页面的 `Web` 组件应先加载普通 shell HTML（`resource://rawfile/`），再通过
  `local-asset://assets.demo.local/static/*` 请求静态子资源
- HarmonyOS sample 必须展示 CSS、脚本和图片等子资源命中成功后的页面结果
- HarmonyOS sample 必须在同一页面中同时展示两张同类图片资源：一张通过 `local-asset://` 命中并被库接管，
  另一张不被库接管并按 ArkWeb 内核默认资源加载路径正常显示
- 不被库接管的那张对照图片可直接使用外部 `https://` 图片资源，但验收重点是"默认加载路径未被库接管"，而不是协议本身
- 静态资源映射应通过正式规则映射 API（`LocalAssetBuilder.addResolver` + `RawfileDirectoryResolver`）接入，
  而不是 sample 私有 resolver 逻辑

### 用例 13.2 Directory Routing Flow

要求：

- HarmonyOS sample 必须展示 `host + path prefix -> 私有目录` 的批量静态资源映射
- 页面中应有一组来自同一路径规则的 CSS、脚本和图片资源
- 规则映射必须复用正式 builder + 正式映射类型（`FileDirectoryResolver`），而不是 sample 私有分支逻辑
- `FilePath` 来源默认 fail-closed，故该场景必须通过正式 `addAllowedFileRoot` 声明允许根，而非绕过 policy

### 用例 13.3 Handle Lifecycle Flow

要求：

- HarmonyOS sample 必须展示 `registerHandle` 返回的 `local-asset://<host>/handles/<token>/<file>` capability URI：
  不可猜测、可吊销、会过期
- 页面必须显式展示该 URI，并以 `<img>` 渲染其承载的资源
- 必须提供"TTL 到期"与"显式吊销"两条路径，并在之后对同一 URI 再次访问，
  验证其不再解析为 `RESOLUTION_ERROR`（stage `resolve`）
- 必须提供原生 `resolveHandle` 探测入口，把成功/失败（category + stage）回传 H5 可见
- 句柄反查/吊销/过期必须复用正式 `HandleRegistry` 能力，而非 sample 私有 store
- **HarmonyOS 特有说明**：token 熵源为系统 CSPRNG 优先（`@ohos.security.cryptoFramework`），不可用时默认抛错
  （fail-loud），仅本地单测沙箱经显式开关放行后才回退 `Math.random()`（见 `harmony/README.md` §9.3）。
  "不可猜测"这一条在真机上已达成，不再是待复测的安全债（见 `docs/threat-model.md` §3.3/§4.2）。

### 用例 13.4 Security Models Flow

要求：

- HarmonyOS sample 必须在同一页面对比两条注册路径的访问控制模型（参见 `docs/design.md §5.4`）：
  - Handle 路径（capability）：`registerHandle` 注册，`scope = null`，不受作用域约束，任意上下文可解析
  - Registry 路径（namespace/scope）：`ResourceDescriptor` 以 `scope = ENGINE` 注册，
    仅当 `descriptor.namespace == context.engineScope` 时通过，否则 `SECURITY_ERROR`（stage `policy_post`）
- 必须同时展示"namespace 匹配"（渲染成功）与"namespace 不匹配"（拒绝渲染）两种 Registry 结果
- 必须提供原生 `engine.resolveUrl` 探测入口，对不匹配 URL 返回 `SECURITY_ERROR / policy_post`，使错误类别在 H5 可见
- 上下文 `engineScope` 必须通过正式 webview 桥接（`HarmonyResolveContextFactory` 的 `engineScope` 入参，
  经 `LocalAssetSchemeHandler` 注入）注入，而非 sample 私有 hack

### 用例 13.5 Error Categories Flow

要求：

- HarmonyOS sample 必须在同一页面触发四类错误，并通过原生 `engine.resolveUrl` 捕获失败，
  把 `category + stage` 回传 H5 展示：
  - `PARSE_ERROR`（stage `adapter_parse`）—— 非法 URL（如 `local-asset://`，无 host）
  - `RESOLUTION_ERROR`（stage `resolve`）—— 无 resolver 命中
  - `LOAD_ERROR`（stage `load`）—— `FilePath` 源在允许根下但缺失（postCheck 通过后由 loader 拒绝）
  - `SECURITY_ERROR`（stage `policy_post`）—— Registry ENGINE scope 下 `namespace != engineScope`
- 四类错误必须复用正式 `EngineResult` 失败态的 category + stage，而非 sample 自造分类
- 上下文 `engineScope` 与允许文件根必须通过正式 builder 配置注入

### 用例 13.6 Resolver Chain Override Flow

要求：

- HarmonyOS sample 必须展示 resolver 链路短路（参见 `docs/design.md §3.4`）：链首的自定义 `ResourceResolver`
  对特定路径返回 `Hit` 即终止，其余路径返回 `Skip` 落到链尾的基础目录 resolver
- 必须在同一命名空间下展示"被覆盖路径"（由自定义 resolver 命中，DYNAMIC，`?mode=` 驱动）
  与"基础路径"（由目录 resolver 命中，STATIC）两种结果
- 自定义 resolver 与目录 resolver 必须复用正式 `addResolver` + 正式映射类型，而非 sample 私有分支
- `?mode=` 驱动的动态解析必须体现 DYNAMIC 资源类型
- 自定义 resolver 的匹配条件（host + path）必须与共享 HTML 请求的 URL 同源（抽为共享常量并由测试钉死），
  否则改动 resolver 里的字面量会让页面静默落到基础目录而不报错

### 用例 13.7 Graceful Degradation Flow

要求：

- HarmonyOS sample 必须展示 H5 侧的优雅降级：页面同时请求多条 `local-asset://` 子资源，
  其中包含有效资源、刻意缺失的静态资源、以及一条已吊销的 handle URI
- 已吊销 handle URI 必须通过正式 `registerHandle` + `removeHandle` 产生，而非 sample 私有不可解析 URI
- 缺失与吊销资源必须通过 H5 error 事件降级，页面保持稳定不崩溃
- 有效资源必须正常加载，与降级资源形成对照
- **HarmonyOS 特有说明**：已进入管线的失败由桥接层构造 404 响应（而非 `didFailWithError`），
  H5 侧据此触发 error 事件；未被 adapter 识别的请求则由 `onRequestStart` 返回 `false` 交还内核。

### 用例 13.8 JSBridge Image Picker Flow

要求：

- HarmonyOS sample 必须展示 Web 通过 JSBridge（`javaScriptProxy`）发起原生选图
- 选中的图片预览必须通过可解析、可反查的 `previewUri` 返回给 WebView；URI 的内部编码格式属于实现细节，
  不作为产品契约的一部分
- Web 点击提交时必须回传 `previewUri`，而不是 token
- Native 在提交阶段必须先解析 `previewUri`，并根据解析结果还原选图记录
- 这项"由资源 URI 反查 Native 资源句柄"的能力应由正式库能力提供，而不是长期依赖 sample 私有 store/codec 维持
- 推荐由独立的 `HandleRegistry` 或平台等价正式能力承担这项职责，而不是把句柄反查硬塞进普通 `ResourceRegistry`
- HarmonyOS sample 当前通过 `metadata["harmony.picker_uri"]` 从 handle 记录中取回原始来源；
  该 key 属于 HarmonyOS 宿主约定，**不属于跨平台正式契约**，与 Android 的 `metadata["android.content_uri"]`
  一一对应（§12.8 对那个 key 有同样的措辞）。库本身不认识这个 key：`metadata` 对 core 而言只是一张不透明的字符串表。
- 提交后，sample 必须展示 Native 还原后的业务可用结果：
  `contentUri`、`localCachePath`、`fileName`、`mimeType`、`size`
- `localCachePath` 应表示 Native 基于原始选图记录生成的业务可用落地文件，而不是仅返回预览缓存路径
- JSBridge 页不得引入 SDK 正式公开面的 demo 专用 API

### 13.9 Fixture 对齐要求

要求：

- `harmony-sample-flows.json` 中定义的每个 sample flow 都必须在 sample 中有对应演示入口
- sample 演示流名称、输入 URL 与预期语义必须与 fixture 保持一致
- 若 sample 新增演示页面且会进入正式验收范围，必须先更新此处用例和对应 fixture

### 13.10 当前验收状态

**已在真机验收通过**（HUAWEI FMR0223C13000767，HarmonyOS 5.0，2026-08-05）。
以下 6 条经设备实测确认渲染与行为正确：§13.1 静态映射（CSS/JS/图片全部命中，双图对照成立）、
§13.2 目录路由、§13.3 句柄生命周期、§13.4 两套安全模型（Handle 与 Registry 两栏渲染成功，
mismatch 栏如期 `SECURITY_ERROR @ policy_post`）、§13.6 解析器短路覆盖、§13.7 优雅降级
（有效资源渲染，缺失/已吊销两条如期降级）。§13.5、§13.8 尚未逐条走完（后者需真人选图）。

验收中暴露并修复的两个缺陷，都**只在真机上才可见**，编译与单测全绿：

1. **`WebSchemeHandlerResponse.setUrl()` 造成无限重定向。** 它不是"这条响应对应哪个 URL"，
   SDK 原文是 *"the resolved URL **after redirects**"* —— 重定向目标。设成请求自身 URL
   等于"重定向到自己"，内核照做，全部子资源报 `ERR_TOO_MANY_REDIRECTS`。不设置即表示
   没有重定向。该调用自首个版本就在，属既有缺陷。
2. **`onHandleUri` 传了对象而非裸字符串。** 共享 HTML 把该参数直接拼进 `<img src="${uri}">`，
   传对象即 `[object Object]`，表现为一张碎图，无任何错误指向真因。

两者的共同点：**失败不产生可读信号** —— 页面一片空白，日志里也没有指向真因的行。定位它们
靠的是临时给 `pages/Index.ets` 的 `Web` 组件挂 `onErrorReceive` / `onConsole`，把内核错误码
与 JS 异常摆到页头（第 1 条即由此一次定位：`net: ERR_TOO_MANY_REDIRECTS ← local-asset://...`）。
验收结束后已移除，页面保持与 Android / iOS 一致的干净形态。**再遇到同类"页面全白"的问题，
先把这两个回调加回去**，比读代码推断快得多。

`onFailure` 覆盖不到这一半：它只在请求**进了** handler 之后才有值，而这两个缺陷一个发生在
内核的重定向环节、一个发生在 JS 侧，都在 handler 之外。

- 已由自动化测试覆盖的部分：core 引擎全链路、桥接决策逻辑（`SchemeRequestHandler`/`BridgeResponse`/目录 resolver）、
  sample 的纯逻辑部分（错误探针四类分类、override banner 的 resolver 匹配与 DYNAMIC 产出、JSBridge 载荷编解码、
  文件工具、`DemoEngine` 的 resolver 链装配、自定义 scheme 的四个开关）。
- ArkWeb 没有 Robolectric 等价物，`LocalAssetSchemeHandler` 的适配层跑不进 `hvigorw test`（只编译不执行），
  因此本章要求的"页面结果""渲染成功/拒绝渲染""error 事件降级"等**视觉断言只能由真机验收兑现**。
- `WebCustomScheme` 的 `isSecure` / `isLocal` / `isDisplayIsolated` 三个开关**刻意留空**。
  验收期间试过 `isSecure: true`（设想它能解决跨源子资源被拦），真机结果反而更糟，已回退。
  这类开关只有真机能验证，改动前必须先有设备结论。
