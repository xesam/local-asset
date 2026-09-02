#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

run_android() {
    echo "--- Android ---"
    cd "$REPO_ROOT/android"
    ./gradlew test --rerun-tasks
    total=0; failures=0; errors=0
    while IFS= read -r -d '' xml; do
        t=$(grep -o 'tests="[0-9]*"' "$xml" 2>/dev/null | head -1 | grep -o '[0-9]*')
        f=$(grep -o 'failures="[0-9]*"' "$xml" 2>/dev/null | head -1 | grep -o '[0-9]*')
        e=$(grep -o 'errors="[0-9]*"' "$xml" 2>/dev/null | head -1 | grep -o '[0-9]*')
        total=$((total + ${t:-0})); failures=$((failures + ${f:-0})); errors=$((errors + ${e:-0}))
    done < <(find . -path '*/build/test-results/*/TEST-*.xml' -print0)
    echo "Android: $total tests, $failures failures, $errors errors"
    # Assert total > 0 for the same reason run_harmony asserts "Tests run" > 0: if the find matches
    # no TEST-*.xml (renamed output dir, skipped Gradle task, build that died before the test phase)
    # all three counters stay at their initialised 0 and "failures == 0 && errors == 0" reports a
    # pass on zero tests. "Nothing ran" must fail, not look like green.
    if [ "$total" -eq 0 ]; then
        echo "Android: no test result XML found — no tests ran"
        return 1
    fi
    [ "$failures" -eq 0 ] && [ "$errors" -eq 0 ]
}

run_ios() {
    echo "--- iOS ---"
    ios_failed=0
    for pkg in localasset-core localasset-webview; do
        echo "  swift test: $pkg"
        (cd "$REPO_ROOT/ios/$pkg" && swift test) || ios_failed=1
    done

    # 上面两个 SPM 包**不包含 sample 工程**：sample 的 view controller、桥、引擎装配
    # 全在 Xcode target 里，swift test 一行都不编。而那部分没有任何测试手段（无 UI harness），
    # 编译是唯一的防线 —— 与 run_harmony 末尾补 assembleHap 是同一条理由。
    echo "  xcodebuild: sample"
    if ! (cd "$REPO_ROOT/ios/sample" && xcodebuild -project LocalAssetSample.xcodeproj \
        -scheme LocalAssetSample -sdk iphonesimulator \
        -destination 'generic/platform=iOS Simulator' build > /tmp/localasset-ios-sample.log 2>&1); then
        echo "iOS: sample build failed"
        grep -E 'error:' /tmp/localasset-ios-sample.log | head -20
        ios_failed=1
    fi
    return $ios_failed
}

HARMONY_MODULES="localasset-core localasset-webview sample"

harmony_result_file() {
    echo "$REPO_ROOT/harmony/$1/.test/default/intermediates/test/coverage_data/test_result.txt"
}

run_harmony() {
    echo "--- HarmonyOS ---"
    # Overridable so the "toolchain missing" branch can be exercised without uninstalling anything.
    local deveco="${DEVECO_STUDIO_HOME:-/Applications/DevEco-Studio.app/Contents}"
    local hvigorw="$deveco/tools/hvigor/bin/hvigorw"
    local ohpm="$deveco/tools/ohpm/bin/ohpm"

    # A contributor without DevEco Studio must still be able to run the Android/iOS suites,
    # so a missing toolchain skips rather than fails. Printed loudly so it is not read as a pass.
    if [ ! -x "$hvigorw" ] || [ ! -d "$deveco/sdk" ]; then
        echo "HarmonyOS: SKIPPED (DevEco Studio not found at $deveco)"
        return 0
    fi

    export PATH="$deveco/tools/node/bin:$PATH"
    export NODE_HOME="$deveco/tools/node"
    export DEVECO_SDK_HOME="$deveco/sdk"

    cd "$REPO_ROOT/harmony"
    "$ohpm" install --all > /dev/null 2>&1 || true

    local log="$REPO_ROOT/harmony/.harmony-test.log"

    # test_result.txt is a persistent file, not a per-run one: if a module's test phase is
    # skipped/filtered out, or fails before any case runs, the previous run's file survives
    # verbatim and the gate reads a stale green. A content check cannot tell fresh from stale
    # (verified: back-dating the file leaves the "Tests run/Failure" line identical). So delete
    # the old results first, making "file missing" a reliable signal that this run produced nothing.
    local module result
    for module in $HARMONY_MODULES; do
        rm -f "$(harmony_result_file "$module")"
    done

    "$hvigorw" test --no-daemon --rerun-tasks > "$log" 2>&1 || true

    # hvigorw test still prints BUILD SUCCESSFUL and exits 0 when test cases fail, so $? is useless.
    # (Compile failures DO exit 255 without printing BUILD SUCCESSFUL, so the grep below covers those.)
    local plain
    plain="$(sed 's/\x1b\[[0-9;]*m//g' "$log")"

    if ! grep -q "BUILD SUCCESSFUL" <<<"$plain"; then
        echo "HarmonyOS: build failed"
        grep -E "ERROR" <<<"$plain" | head -20
        return 1
    fi

    # The authoritative signal is each module's machine-readable result file, whose last line reads
    # "Tests run: 7, Failure: 0, Error: 0, Pass: 7, Ignore: 0".
    # Asserting "Tests run" > 0 is mandatory: grepping only for failures cannot distinguish
    # "everything passed" from "not a single case ran" (a missing List.test.ets registration is
    # silently green under both). Hence the [1-9][0-9]* rather than [0-9]+.
    local total=0
    local last
    for module in $HARMONY_MODULES; do
        result="$(harmony_result_file "$module")"
        if [ ! -f "$result" ]; then
            echo "HarmonyOS: $module produced no test result file"
            return 1
        fi
        last="$(tail -1 "$result")"
        if ! grep -qE "Tests run: [1-9][0-9]*, Failure: 0, Error: 0" <<<"$last"; then
            echo "HarmonyOS: $module -> $last"
            grep -E "ERROR: Error in " <<<"$plain" | head -20
            return 1
        fi
        total=$((total + $(sed -E 's/Tests run: ([0-9]+).*/\1/' <<<"$last")))
    done

    # `hvigorw test` 只编译被测模块的 test 目标，**不编译 sample 的 main 源码**
    # （实测：往 sample/src/main/ets 里塞一条必然的类型错误，test 依然全绿——各模块用例照跑、一条不红）。
    # 而 sample 的 main 里正是 ArkUI 页面、桥、引擎装配所在 —— 那部分只能靠编译发现问题，
    # 本仓没有任何 UI 测试手段。因此必须再跑一次 assembleHap，把编译这一关补上。
    #
    # 签名失败不应阻塞测试门禁：assembleHap 包含编译和签名两个阶段，签名阶段（SignHap）
    # 依赖本机证书（~/.ohos/config/...），是环境问题而非代码问题。HarmonyOS 的 .p7b profile
    # 绑定华为开发者账号 + 设备 UDID，无法像 Android debug keystore 那样跨账号共享，
    # 因此全新 clone 缺签名是正常的。只要编译通过，门禁就算通过。
    if ! "$hvigorw" --mode module -p module=entry@default -p product=default \
        -p requiredDeviceType=phone assembleHap --no-daemon > "$log" 2>&1; then
        local clean_log
        clean_log="$(sed 's/\x1b\[[0-9;]*m//g' "$log")"
        # 区分签名失败与编译失败：SignHap / certificate / signingConfig 关键字表明编译已过
        if grep -qE 'SignHap|certificate has expired|Certificate format|signingConfig|appCertFile|No signing' <<<"$clean_log"; then
            echo "HarmonyOS: sample compiled OK, HAP signing skipped (no/expired certificate)"
            echo "  → to build a installable HAP, see harmony/signing-config.local.json.template"
        else
            echo "HarmonyOS: sample HAP build failed"
            grep -E "ERROR" <<<"$clean_log" | head -20
            return 1
        fi
    fi

    echo "HarmonyOS: $total tests, 0 failures, 0 errors; sample HAP built"
    return 0
}

echo "=== LocalAsset Test Suite ==="
android_ok=0; ios_ok=0; harmony_ok=0
run_android && android_ok=1 || true
run_ios     && ios_ok=1     || true
run_harmony && harmony_ok=1 || true

echo ""
[ $android_ok -eq 1 ] && echo "Android: PASSED" || echo "Android: FAILED"
[ $ios_ok     -eq 1 ] && echo "iOS:     PASSED" || echo "iOS:     FAILED"
[ $harmony_ok -eq 1 ] && echo "Harmony: PASSED" || echo "Harmony: FAILED"
echo ""

[ $android_ok -eq 1 ] && [ $ios_ok -eq 1 ] && [ $harmony_ok -eq 1 ] && echo "=== All tests passed ===" && exit 0
echo "=== Tests FAILED ===" && exit 1
