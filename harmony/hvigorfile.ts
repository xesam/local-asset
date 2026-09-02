import { appTasks } from '@ohos/hvigor-ohos-plugin';

/**
 * 生成 harmony/localasset-core/src/test/compat/FixtureRoot.generated.ets。
 *
 * 为什么必须在这里生成（Task 11 实测结论，勿凭直觉改回相对路径）：
 * 单元测试运行在 ArkTS 沙箱里，**没有可用的工作目录概念** ——
 *   - `fs.accessSync('../docs/...')` 及其余各级相对路径恒为 false；
 *   - 用相对路径写文件抛 `Operation not permitted`（沙箱不解析相对路径）；
 *   - `fs.listFileSync` 在该环境下 `undefined is not callable`，无法反推 cwd；
 *   - `process.getEnvironmentVar('PWD'/'HOME'/自定义名)` 一律返回空串，环境变量传不进去；
 *   - `__dirname` / `process.cwd()` 在 ArkTS 侧不可用（arkts-strict-typing 直接拒编）。
 * 即：测试进程只吃**绝对路径**，而绝对路径又不允许硬编码进仓库。
 *
 * hvigorfile.ts 则跑在普通 Node 上下文里，`__dirname` 与 `process.cwd()` 都指向
 * harmony/ 工程根（已实测：两者皆为 <repo>/harmony），因此由它在每次构建时把仓库根
 * 算出来写成常量，测试再 import 这个常量 —— 提交的代码里不出现任何机器相关的绝对路径。
 *
 * 生成物已在 harmony/.gitignore 中忽略；hvigor 每次调用都会重新生成，
 * 所以全新 clone 直接跑 `hvigorw test` 即可，无需额外准备步骤。
 */
function generateFixtureRoot(): void {
  const fs = require('fs');
  const path = require('path');
  // __dirname === <repo>/harmony
  const repoRoot = path.resolve(__dirname, '..');
  const fixtureRoot = path.join(repoRoot, 'docs', 'compatibility-fixtures');
  const outDir = path.join(__dirname, 'localasset-core', 'src', 'test', 'compat');
  const outFile = path.join(outDir, 'FixtureRoot.generated.ets');
  const content =
    '// 由 harmony/hvigorfile.ts 在每次构建时生成，请勿手工编辑（已被 .gitignore 忽略）。\n' +
    'export const FIXTURE_ROOT = ' + JSON.stringify(fixtureRoot) + ';\n';
  fs.mkdirSync(outDir, { recursive: true });
  if (!fs.existsSync(outFile) || fs.readFileSync(outFile, 'utf-8') !== content) {
    fs.writeFileSync(outFile, content);
  }
}


/**
 * 从 `signing-config.local.json` 读签名配置，注入构建。
 *
 * ## 为什么不放在 build-profile.json5 里
 *
 * DevEco Studio 会在首次运行/调试时**自动**把签名配置回写进 `build-profile.json5`，
 * 而那份配置是机器相关且含密钥口令的：
 *   - `certpath` / `profile` / `storeFile` 指向 `~/.ohos/config/...` 的绝对路径，
 *     换台机器就不存在，clone 下来直接构建失败；
 *   - `keyPassword` / `storePassword` 是能解开 .p12 的口令，进了 git 历史就删不干净。
 *
 * 但整个文件又不能 gitignore —— `modules`（三个模块的声明）与 `products`（SDK 版本、
 * strictMode）是全团队必须一致的工程结构，缺了 hvigor 不知道要构建什么。
 *
 * 所以只把**因人而异的那一段**外置：`signingConfigs` 在提交版本里保持 `[]`，
 * 实际材料放进 gitignore 的 `signing-config.local.json`，由本函数在构建期注入
 * `config.ohos.overrides.signingConfig`（`AppOhosConfig.Overrides`，插件原生支持）。
 *
 * ## 没有这个文件时会怎样
 *
 * 返回 undefined，构建照常进行 —— `hvigorw test` 与各 HAR 模块的构建都不需要签名。
 * 只有 `assembleHap` 会因缺签名而失败，那时按提示复制模板即可。刻意不在这里抛错：
 * 让「只想跑测试」的贡献者无需准备任何签名材料。
 *
 * 同一模式在本文件的 generateFixtureRoot 与 sample/hvigorfile.ts 的 syncSharedDemo
 * 里已有先例：凡是机器相关或属于构建产物的东西，一律构建期生成 + gitignore。
 */
function loadSigningConfig() {
  const fs = require('fs');
  const path = require('path');
  const configFile = path.join(__dirname, 'signing-config.local.json');
  if (!fs.existsSync(configFile)) {
    return undefined;
  }
  const raw = fs.readFileSync(configFile, 'utf-8');
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (e) {
    // 大声失败：配置存在但读不出来，是笔误而非「没配」，静默忽略只会让人对着
    // 「签名缺失」的报错去查签名本身，而真正的原因在这个文件的语法里。
    throw new Error('signing-config.local.json 解析失败：' + e.message);
  }
  // override 的 schema **只接受 material 与 type**（实测：多带一个 name 会让构建以
  // "Schema validate failed ... propertyName: 'name'" 失败）。`name` 不属于这里 ——
  // 它由 build-profile.json5 的 signingConfigs 提供，而那份配置正是本机制要摘掉的。
  // 所以只取这两个字段，模板里的 "//" 注释键与 name 一并丢弃。
  const material = parsed.material;
  if (!material) {
    throw new Error('signing-config.local.json 缺少 material 字段，参照 signing-config.local.json.template 填写。');
  }
  return parsed.type ? { material, type: parsed.type } : { material };
}

generateFixtureRoot();

const signingConfig = loadSigningConfig();

export default {
  system: appTasks,
  plugins: [],
  // signingConfig 为 undefined 时整个 overrides 省略 —— 传一个 {signingConfig: undefined}
  // 会让插件拿到一个「声明了但没值」的 override，行为不如干脆不声明来得确定。
  config: signingConfig ? { ohos: { overrides: { signingConfig } } } : {}
}
