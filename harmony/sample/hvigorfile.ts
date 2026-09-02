import { hapTasks } from '@ohos/hvigor-ohos-plugin';

/**
 * 把 shared/demo/ 同步进 entry 模块的 rawfile。
 *
 * ## 为什么必须挂进构建
 *
 * Android 用 Gradle sourceSets 把 ../../shared 挂进 assets，iOS 用 Xcode 的
 * folder reference —— 两端都是构建期自动生效，clone 下来直接构建即可。
 * HarmonyOS 的 rawfile 没有等价的多目录挂载能力，只能物理复制；复制结果是
 * 构建产物，已在 harmony/.gitignore 中排除。
 *
 * 若只提供 scripts/sync-harmony-demo.sh 让人手工执行，全新 clone 直接跑
 * `hvigorw assembleHap` 会**静默**产出一个 rawfile/demo 为空的 HAP ——
 * 构建成功、退出码 0、日志无任何提示，装上去每个演示页面白屏。
 * 这与脚本自身「缺 shared/demo 就报错退出」的防御是同一类问题，只是上移了一层。
 * 因此在这里同步，`assembleHap` 就不可能产出没有演示内容的 HAP。
 *
 * 同一模式在 harmony/hvigorfile.ts 里已有先例：FixtureRoot.generated.ets
 * 也是每次构建重新生成，正是为了让全新 clone 无需任何准备步骤。
 *
 * ## 与 scripts/sync-harmony-demo.sh 的关系
 *
 * 那个脚本仍是独立可用的入口（README 会引用它，也方便不走构建时单独同步）。
 * 这里刻意用 Node 重写了它那几行逻辑，而不是 `execFileSync('bash', ...)` 去调它：
 * 调 bash 会给构建平白引入一个 shell 依赖（Windows 上 DevEco 未必有 bash），
 * 届时构建会因为「找不到 bash」而失败，而不是因为真的缺内容 —— 得不偿失。
 * 重复的逻辑只有下面几行，两边语义必须保持一致：
 * 先删后拷（保证幂等、且 shared/demo 中已删除的文件不会作为残留滞留）、
 * 源目录缺失即报错退出（绝不静默产出空目录）。
 */
function syncSharedDemo(): void {
  const fs = require('fs');
  const path = require('path');
  // __dirname === <repo>/harmony/sample
  const repoRoot = path.resolve(__dirname, '..', '..');
  const src = path.join(repoRoot, 'shared', 'demo');
  const dest = path.join(__dirname, 'src', 'main', 'resources', 'rawfile', 'demo');

  if (!fs.existsSync(src)) {
    // 大声失败：一个静默 no-op 的构建钩子比没有钩子更糟 —— 它看起来运行过了。
    throw new Error(
      'sync-harmony-demo: shared/demo not found at ' + src +
      '. entry 模块的演示内容源自 shared/demo，缺失时拒绝产出空的 rawfile/demo。'
    );
  }

  fs.rmSync(dest, { recursive: true, force: true });
  fs.mkdirSync(dest, { recursive: true });
  fs.cpSync(src, dest, { recursive: true });
}

syncSharedDemo();

export default {
  system: hapTasks,
  plugins: []
}
