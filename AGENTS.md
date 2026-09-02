## Repository Guidelines

### Test Gate

**After every code change, all platform tests must pass before the work is considered complete.**

```bash
bash scripts/test.sh   # runs Android + iOS + HarmonyOS tests; must exit 0
```

Individual platform commands:
```bash
# Android (from android/)
./gradlew test

# iOS
cd ios/localasset-core    && swift test
cd ios/localasset-webview && swift test

# HarmonyOS (from harmony/) — needs DevEco Studio
"$DEVECO_STUDIO_HOME/tools/hvigor/bin/hvigorw" test --no-daemon --rerun-tasks
```

Never report a task as done if `scripts/test.sh` fails.

> **⚠️ "All tests passed" is weaker than it reads without DevEco Studio.**
> `run_harmony()` **skips and returns success** when DevEco Studio is absent
> (`scripts/test.sh:55-58`). This is deliberate — a contributor without the HarmonyOS
> toolchain must still be able to run the Android/iOS suites — and the skip is printed
> loudly (`HarmonyOS: SKIPPED (...)`). But it means a green run on such a machine,
> **including CI**, has verified only Android and iOS. When touching `harmony/`, confirm
> the output says HarmonyOS ran rather than trusting the final `=== All tests passed ===`.

> **⚠️ Sample apps are covered by compilation only — and that coverage had to be added.**
> `swift test` builds only the two SPM packages, and `hvigorw test` builds only each module's
> test target; neither touches the sample apps. Verified by injecting a guaranteed type error
> into `harmony/sample/src/main/` — `scripts/test.sh` still printed `=== All tests passed ===`,
> while `assembleHap` failed. `run_ios()` and `run_harmony()` therefore end with an explicit
> `xcodebuild build` / `assembleHap`; both were confirmed to turn the gate red. (Android's
> `./gradlew test` already compiles sample `main`, confirmed the same way.)
>
> **HarmonyOS `assembleHap` signing failures are non-blocking.** The `.p7b` provisioning profile
> is tied to a Huawei developer account + device UDID and cannot be bundled in the repo like an
> Android debug keystore. When `assembleHap` fails with a signing-related error (expired
> certificate, missing config), `test.sh` reports a warning and continues — the compilation
> check has already passed at that point. Only compilation failures (type errors, missing
> imports) cause the gate to fail. To build an installable HAP, see
> `harmony/signing-config.local.json.template`.
>
> Compilation is the **only** automated check the sample apps get: their UI, JSBridge wiring,
> and engine assembly have no test harness on any platform. Behavioral regressions there
> surface only in on-device acceptance (`docs/compatibility.md` §12 / §13).

### Project Structure & Module Organization

```
local-asset/
├── android/                         # Android implementation (Gradle, Kotlin DSL)
│   ├── localasset-core/             #   Pure Kotlin engine — no Android framework deps
│   ├── localasset-webview/          #   WebView bridge (WebResourceResponse, CORS)
│   └── sample/                      #   Demo app with 5 example flows
├── ios/                             # iOS implementation (Swift Package Manager)
│   ├── localasset-core/             #   Pure Swift engine — no UIKit/AppKit deps
│   ├── localasset-webview/          #   WKWebView bridge (WKURLSchemeHandler, CORS)
│   └── sample/                      #   Demo app with 5 example flows
├── harmony/                         # HarmonyOS implementation (DevEco Studio, hvigor)
│   ├── localasset-core/             #   Pure ArkTS engine — no ArkUI/ArkWeb deps
│   ├── localasset-webview/          #   ArkWeb bridge (WebSchemeHandler, CORS)
│   └── sample/                      #   Demo app with 8 example flows
├── docs/                            # Design docs & cross-platform specs
│   ├── design.md                    #   Platform-agnostic architecture
│   ├── compatibility.md             #   Cross-platform behavioral contracts
│   └── compatibility-fixtures/      #   Shared JSON test fixtures
└── README.md
```

Android source lives under `io.github.xesam.android.localasset`. Each module maps to a Gradle subproject (`:localasset-core`, `:localasset-webview`, `:sample`). Test sources mirror main sources under `src/test/kotlin/`.

iOS source lives under `LocalAssetCore` / `LocalAssetWebView` Swift modules. Each module is a standalone Swift package under `ios/{module}/`.

HarmonyOS source lives under `io.github.xesam.harmony.localasset.{core,webview}`. Each module is an hvigor subproject under `harmony/{module}/`, with main sources in `src/main/ets/` and tests in `src/test/`. See `harmony/README.md` for toolchain caveats and known cross-platform differences.

### Build, Test, and Development Commands

**Android** — run from `android/`:
```bash
./gradlew build          # Compile all modules
./gradlew test           # Run all tests (core: JVM; webview: Robolectric)
./gradlew :localasset-core:testDebugUnitTest    # Core tests only (fast, no emulator)
./gradlew :localasset-webview:testDebugUnitTest  # WebView bridge tests
./gradlew :sample:testDebugUnitTest              # Sample app tests
./gradlew :localasset-core:testDebugUnitTest --tests "fully.qualified.TestClass"
```

**iOS** — run from repo root:
```bash
cd ios/localasset-core    && swift test
cd ios/localasset-webview && swift test
```

**HarmonyOS** — run from `harmony/` (requires DevEco Studio; `hvigorw` lives under
`$DEVECO_STUDIO_HOME/tools/hvigor/bin/`, default `/Applications/DevEco-Studio.app/Contents`):
```bash
hvigorw test --no-daemon --rerun-tasks   # all three modules
```

> ⚠️ **`hvigorw test`'s exit code is not trustworthy**: it prints `BUILD SUCCESSFUL` and exits 0
> even when test cases fail. `scripts/test.sh` therefore parses each module's
> `test_result.txt` instead, and deletes stale result files first so that "nothing ran"
> cannot read as green. Details in `harmony/README.md`.

Core tests use `kotlin.test` (Android) / `swift test` (iOS) / hypium (HarmonyOS) and run as plain unit tests. Android WebView tests use Robolectric 4.14.1. The `localasset.repo.root` system property is injected automatically for Android fixture resolution. ArkWeb has no Robolectric equivalent, so `LocalAssetSchemeHandler` is compiled but not executed by `hvigorw test`.


### Coding Style & Naming Conventions

**Kotlin (Android)**
- `kotlin.code.style=official`. Indentation: 4 spaces. PascalCase for files/classes; camelCase for functions/properties.
- `sourceCompatibility = JavaVersion.VERSION_21`, JVM toolchain 21.
- Packages mirror directory structure under `io.github.xesam.android.localasset.{module}.{layer}` (e.g., `api/`, `model/`, `engine/`, `resolver/`, `policy/`, `loader/`, `internal/`, `error/`).
- `minSdk = 24`, `compileSdk = 35`, AndroidX required.
- Star imports preferred within project packages; explicit imports for external dependencies.

**Swift (iOS)**
- Swift 5.9+, Swift Package Manager. Indentation: 4 spaces. PascalCase for types; camelCase for functions/properties.
- No UIKit/AppKit in `localasset-core`; WKWebKit only in `localasset-webview`.
- `public` API matches Android counterparts in naming and semantics.

**ArkTS (HarmonyOS)**
- ArkTS / DevEco Studio + hvigor. Indentation: 2 spaces. PascalCase for types; camelCase for functions/properties.
- No ArkUI/ArkWeb imports in `localasset-core`; `@kit.ArkWeb` only in `localasset-webview`.
- Modules under `io.github.xesam.harmony.localasset.{core,webview}`; all public symbols are re-exported through each module's `Index.ets` barrel.
- Public API matches Android/iOS counterparts in naming and semantics, except where `harmony/README.md` records a deliberate divergence (e.g. no `Stream` source, `resolveUrl`/`resolveRequest` instead of overloads).

### Testing Guidelines

- **Framework**: `kotlin.test` for Android pure Kotlin; Robolectric 4.14.1 for Android WebView tests; Swift Testing / XCTest for iOS; hypium for HarmonyOS.
- **Naming**: `{ClassName}Test.kt` (Android) / `{ClassName}Tests.swift` (iOS) / `{ClassName}.test.ets` (HarmonyOS) under the corresponding test source root.
- **HarmonyOS**: every registered module needs a `src/test/List.test.ets` that registers its suites, even if it has no cases — an unregistered suite silently does not run.
- **Fixtures**: shared cross-platform test fixtures live in `docs/compatibility-fixtures/` as JSON.
- **Coverage**: no enforced threshold. Focus tests on the engine pipeline (parsing, resolution, policy enforcement, loading) since every request must pass through it.


### Commit & Pull Request Guidelines

- **Commits**: concise and imperative (e.g., "Add directory routing resolver").
- **PR descriptions**: summary of what changed, why, and which modules are affected. Link to the relevant design doc section if the change touches cross-platform behavior (consult `docs/compatibility.md` and fixtures).

### Architecture Overview

The engine pipeline processes every request in this order:

1. **SchemeAdapter** — parse URL → `AssetRequest`
2. **Policy.preCheck** — request-level security gate
3. **ResolverChain** — ordered resolvers, short-circuit on first `Hit`/`Failure`:
   - `HandleRegistryResolver` (always first, reverse-lookups handle URIs)
   - User-registered resolvers
   - `RegistryResolver` (fallback, lookup by stored ID)
4. **Policy.postCheck** — resource-level security gate (TTL, scope, file-root)
5. **Loader** — load bytes from `Bytes` or `FilePath` source
6. **ResponseBuilder** — platform-specific response (`WebResourceResponse` on Android, `URLSchemeTask` response on iOS, `BridgeResponse` → `WebResourceHandler` on HarmonyOS)

Failures are categorized as `PARSE_ERROR`, `RESOLUTION_ERROR`, `LOAD_ERROR`, or `SECURITY_ERROR` and tagged with the stage where they occurred. This pipeline and error taxonomy are identical across platforms; see `docs/compatibility.md` for behavioral contracts.
