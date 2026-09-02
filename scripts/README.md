# scripts/ 目录说明

仓库辅助脚本。每个脚本的设计原因如下，避免重复答疑。

## 目录

1. [test.sh — 全平台测试门禁](#1-testsh--全平台测试门禁)
2. [sync-harmony-demo.sh — 同步演示内容到 HarmonyOS rawfile](#2-sync-harmony-demosh--同步演示内容到-harmonyos-rawfile)
3. [mutate.sh — HarmonyOS 变异测试 harness（harmony/scripts/）](#3-mutatesh--harmonyos-变异测试-harnessharmonyscripts)

---

## 1. test.sh — 全平台测试门禁

一键运行 Android + iOS + HarmonyOS 三端测试，退出码 0 表示全部通过。

```bash
bash scripts/test.sh
```

### 1.1 各平台执行内容

| 平台 | 执行命令 | 测试框架 | 额外检查 |
|------|---------|---------|---------|
| Android | `./gradlew test` | kotlin.test + Robolectric 4.14.1 | 解析 TEST-*.XML 汇总，断言 total > 0 |
| iOS | `swift test` × 2 包 + `xcodebuild build` sample | Swift Testing / XCTest | sample 工程仅编译验证（无 UI 测试） |
| HarmonyOS | `hvigorw test` + `assembleHap` | hypium | 解析 test_result.txt，断言 Tests run > 0；sample HAP 编译验证 |

### 1.2 签名失败不阻塞门禁

HarmonyOS 的 `assembleHap` 包含编译和签名两个阶段。签名依赖本机证书（`~/.ohos/config/...`），而 `.p7b` profile 绑定华为开发者账号 + 设备 UDID，无法像 Android debug keystore 那样跨账号共享。因此全新 clone 缺签名是正常的。

`test.sh` 在 `assembleHap` 失败时区分两类错误：

| 错误类型 | 日志关键字 | 处理 |
|---------|----------|------|
| 签名失败 | `SignHap` / `certificate has expired` / `signingConfig` / `appCertFile` | 编译已通过，输出 warning，**不阻塞门禁** |
| 编译失败 | 其他 ERROR | **阻塞门禁** |

要构建可安装的 HAP，按 `harmony/signing-config.local.json.template` 配置签名。

### 1.3 设计要点

**DevEco Studio 缺失时跳过 HarmonyOS**：没有 HarmonyOS 工具链的贡献者仍应能运行 Android/iOS 套件，因此跳过而非失败。跳过会显式打印 `HarmonyOS: SKIPPED (...)`。但这意味着在这类机器上的绿色运行只验证了 Android 和 iOS——修改 `harmony/` 时需确认输出确实显示 HarmonyOS 执行了。

**"零测试"视为失败**：Android 断言 total > 0，HarmonyOS 断言 `Tests run: [1-9]`——如果测试阶段被跳过或构建在测试前中断，计数器停留在 0，"0 failures"不能被误读为绿色。

**sample 应用仅由编译覆盖**：`swift test` 不触碰 Xcode 工程的 sample target，`hvigorw test` 不编译 sample 的 main 源码。两者末尾分别补了 `xcodebuild build` / `assembleHap`，把编译这一关补上。HarmonyOS `assembleHap` 的签名失败不阻塞门禁（见 1.2），编译失败仍然阻塞。

**hvigorw 退出码不可信**：`hvigorw test` 即使测试用例失败也打印 `BUILD SUCCESSFUL` 并退出 0。脚本改为解析各模块的 `test_result.txt`，并在运行前删除旧结果文件，防止"什么都没跑"被误判为绿色。

---

## 2. sync-harmony-demo.sh — 同步演示内容到 HarmonyOS rawfile

把 `shared/demo/` 的 Web 演示页面物理复制到 HarmonyOS 示例应用的 rawfile 目录。

```bash
bash scripts/sync-harmony-demo.sh
```

### 2.1 为什么需要这个脚本

`shared/demo/` 存放三端示例应用共用的 Web 页面（HTML/CSS/JS）。三端处理方式不同：

| 平台 | 挂载方式 | 需要物理复制 |
|------|---------|------------|
| Android | Gradle sourceSets 把 `../../shared` 挂进 assets | 否 |
| iOS | Xcode folder reference | 否 |
| HarmonyOS | rawfile 无等价的多目录挂载能力 | **是** |

HarmonyOS 的 rawfile 只能访问 `src/main/resources/rawfile/` 下的文件，无法引用外部目录，因此必须物理复制。复制结果是构建产物，已在 `harmony/.gitignore` 中排除。

### 2.2 与 hvigorfile.ts 的关系

同样的同步逻辑在 `harmony/sample/hvigorfile.ts` 中用 Node.js 重写了一份，每次 `hvigorw assembleHap` 自动执行。全新 clone 直接构建也不会产出空演示内容的 HAP。

hvigorfile.ts 刻意用 Node 重写而非 `execFileSync('bash', ...)` 调脚本——Windows 上 DevEco 不一定有 bash，调 bash 会让构建因"找不到 bash"而失败，而不是因为真的缺内容。

本脚本保留为独立入口，方便不走构建时单独同步。两边语义必须保持一致：先删后拷（幂等）、源目录缺失即报错退出。

### 2.3 幂等性

每次先 `rm -rf` 目标目录再整体复制，重复执行结果一致，且 `shared/demo` 中删除的文件不会作为残留留在 rawfile 中。

---

## 3. mutate.sh — HarmonyOS 变异测试 harness（harmony/scripts/）

对 HarmonyOS 侧做单点变异（把一处代码替换为指定文本），跑三模块测试，结束后从 `.bak` 还原被改文件。用于验证测试套件真能"杀死"已知类型的缺陷——目录 resolver 的 11 行变异结论即由它产出。

```bash
harmony/scripts/mutate.sh <label> <相对 harmony/ 的文件> <old> <new>
```

两种"假绿"各有防线（详见脚本头部注释）：**变异没落地**（模式必须恰好匹配一次、改写后 `diff -q` 必须报告文件确有变化，否则判结果作废）与**读到上一轮的陈旧结果文件**（跑前删 `test_result.txt`，跑后文件缺失同样判作废）。
