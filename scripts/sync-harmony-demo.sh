#!/usr/bin/env bash
# 把 shared/demo/ 同步进 harmony sample 的 rawfile。
#
# Android 用 Gradle sourceSets 把 ../../shared 挂进 assets，iOS 用 Xcode 的 folder reference；
# HarmonyOS 的 rawfile 没有等价的多目录挂载能力，只能物理复制。因此复制结果是构建产物，
# 已在 harmony/.gitignore 中排除。
#
# 注意：同样的同步逻辑也内建在 harmony/sample/hvigorfile.ts 里，每次构建自动执行 ——
# 所以全新 clone 直接跑 `hvigorw assembleHap` 也不会产出没有演示内容的 HAP，
# 不必先手工执行本脚本。本脚本保留为独立入口，便于不走构建时单独同步。
# 两边语义必须保持一致：先删后拷 + 源目录缺失即报错退出。
#
# 幂等：每次先删掉目标目录再整体复制，所以重复执行结果一致，
# 且 shared/demo 里删除的文件不会作为残留留在 rawfile 中。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO_ROOT/shared/demo"
DEST="$REPO_ROOT/harmony/sample/src/main/resources/rawfile/demo"

if [ ! -d "$SRC" ]; then
    echo "shared/demo not found at $SRC" >&2
    exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$SRC/." "$DEST/"
echo "synced shared/demo -> harmony/sample/src/main/resources/rawfile/demo"
find "$DEST" -type f | wc -l | xargs echo "files:"
