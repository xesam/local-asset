#!/usr/bin/env bash
#
# 变异测试 harness（Task 3 的 11 行变异结果由它产出，可复跑复核）。
#
#   harmony/scripts/mutate.sh <label> <相对 harmony/ 的文件> <old> <new>
#
# 例（复现 Task 3 的 M1）：
#   harmony/scripts/mutate.sh "M1 matchesPrefix 去掉分隔符" \
#     localasset-webview/src/main/ets/mapping/DirectoryResolverSupport.ets \
#     "return path === prefix || path.startsWith(prefix + '/');" \
#     "return path.startsWith(prefix);"
#
# ## 两种"假绿"，两道防线
#
# 变异测试的价值全在"变异真的落地了、结果真的是这次跑出来的"。两种失效模式必须分开防：
#
#   A. **变异没落地**（模式拼错、代码已改动导致匹配不上）却按"测试通过"记账。
#      → 防线：模式必须**恰好出现一次**，且改写后 `diff -q` 必须报告文件确有变化，
#        否则打印"结果作废"并 exit 3，绝不进入跑测试环节。
#
#   B. **变异落地了，但读到的是上一次的结果文件**（Task 2 真实踩过这个坑）。
#      本次构建若在编译期就失败，`test_result.txt` 不会被重写，于是读到的是陈旧的绿。
#      → 防线：跑测试**之前**删掉两个模块的 test_result.txt；跑完若文件不存在，
#        说明本次根本没产出结果，同样判为"结果作废"。
#
# 无论成败，结束时一律从 .bak 还原被改的文件。
set -u

if [ "$#" -ne 4 ]; then
  echo "用法: $0 <label> <相对 harmony/ 的文件路径> <old> <new>" >&2
  exit 64
fi

LABEL="$1"; FILE="$2"; OLD="$3"; NEW="$4"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

if [ ! -f "$FILE" ]; then
  echo "=== $LABEL: 目标文件不存在: $FILE" >&2
  exit 3
fi

RESULTS=(
  "localasset-core/.test/default/intermediates/test/coverage_data/test_result.txt"
  "localasset-webview/.test/default/intermediates/test/coverage_data/test_result.txt"
)

restore() { [ -f "$FILE.bak" ] && mv "$FILE.bak" "$FILE"; }
trap restore EXIT

cp "$FILE" "$FILE.bak"

# --- 防线 A：变异必须真的落地 ---
python3 - "$FILE" "$OLD" "$NEW" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
n = s.count(old)
if n != 1:
    print(f"MUTATION-NOT-APPLIED: pattern occurs {n} times (need exactly 1)", file=sys.stderr)
    sys.exit(2)
open(path, 'w').write(s.replace(old, new))
PY
if [ $? -ne 0 ]; then
  echo "=== $LABEL: 变异未落地（模式匹配失败），结果作废"
  exit 3
fi

if diff -q "$FILE.bak" "$FILE" >/dev/null; then
  echo "=== $LABEL: 变异未落地（文件内容未变），结果作废"
  exit 3
fi

echo "=== $LABEL: 变异已落地，diff:"
diff "$FILE.bak" "$FILE" | head -12

# --- 防线 B：清掉上一次的结果，杜绝读到陈旧的绿 ---
for R in "${RESULTS[@]}"; do rm -f "$R"; done

export PATH="/Applications/DevEco-Studio.app/Contents/tools/node/bin:$PATH"
export NODE_HOME="/Applications/DevEco-Studio.app/Contents/tools/node"
export DEVECO_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk"
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw test --no-daemon --rerun-tasks \
  > /tmp/localasset-mutate.log 2>&1
plain="$(sed 's/\x1b\[[0-9;]*m//g' /tmp/localasset-mutate.log)"

# hvigorw 在**运行时用例失败**和**零用例执行**时同样打印 BUILD SUCCESSFUL 并返回 0，
# 所以既不能看 $?，也不能只看这一行 —— 还要读结果文件本身。
if ! grep -q "BUILD SUCCESSFUL" <<<"$plain"; then
  echo "$LABEL: 编译失败（变异被编译器捕获，同样算杀死）"
  grep -oE 'Error Message: [^(]*' <<<"$plain" | sort -u | head -5
  exit 0
fi

for R in "${RESULTS[@]}"; do
  M="${R%%/*}"
  if [ ! -f "$R" ]; then
    echo "$LABEL: $M 未产出结果文件 —— 本次没有跑用例，结果作废"
    exit 3
  fi
  echo "$LABEL: $M: $(tail -1 "$R")"
  python3 - "$R" <<'PY'
import sys
cur = None
for ln in open(sys.argv[1]).read().splitlines():
    if ln.startswith('test='):
        cur = ln[5:]
    elif ln.startswith('result=') and ln != 'result=Success':
        print('  FAILED ->', cur)
PY
done
