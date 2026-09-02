import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import { toArrayBuffer } from 'io.github.xesam.harmony.localasset.webview';

/**
 * rawfile 读取与「rawfile 目录 → 沙箱目录」落地。
 *
 * 本文件刻意**不 import 任何 ArkUI / ArkWeb 类型**：它被 `src/test` 下的用例直接引用，
 * 而 hvigor 的 test 目标编译不进 UI 组件。凡是 @Component 里写得下的逻辑，
 * 都应先看看能不能挪到这里 —— ArkUI 页面在本仓没有任何测试手段（无设备、无 UI 测试
 * harness），落在 struct 体内的代码只能被编译，不能被验证。
 */

/**
 * 读 rawfile；读不到时返回 null 而不是抛错。
 *
 * `getRawFileContentSync` 对不存在的路径**抛异常**（不是返回 null），而 resolver 侧
 * 需要的是「没有就 Skip」这条日常分支，所以在这里就把异常收敛掉。
 * 目录路径同样走进 catch —— `copyTree` 正是靠这一点区分文件与子目录。
 */
export function readRawfileBytes(context: common.UIAbilityContext, path: string): Uint8Array | null {
  try {
    return context.resourceManager.getRawFileContentSync(path);
  } catch (error) {
    return null;
  }
}

/** 列出 rawfile 某个目录下的直接条目；读不到时返回空数组。 */
export function listRawfileEntries(context: common.UIAbilityContext, dir: string): string[] {
  try {
    return context.resourceManager.getRawFileListSync(dir);
  } catch (error) {
    return [];
  }
}

/** 沙箱内的一个目录路径。用 cacheDir 而非 filesDir：演示落地文件是可重建的缓存。 */
export function sandboxDir(context: common.UIAbilityContext, name: string): string {
  return context.cacheDir + '/' + name;
}

/**
 * `copyTree` 的读取面，注入而非直接吃 Context。
 *
 * 理由与 `RawfileDirectoryResolver.readRawfile` 完全相同：`resourceManager` 只能从真实
 * 应用 Context 取得，测试沙箱里没有 Context。注入之后 `copyTree` 这段递归/落盘逻辑
 * 才能被真正测到，而不是只被编译。
 */
export interface RawfileTreeReader {
  /** 列出目录下的直接条目名（不含路径）。 */
  list: (dir: string) => string[];
  /** 读文件字节；路径是目录或不存在时返回 null。 */
  read: (path: string) => Uint8Array | null;
}

export { toArrayBuffer };

/** 把字节写到 path（截断已有内容）。父目录必须已存在。 */
export function writeBytes(path: string, bytes: Uint8Array): void {
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, toArrayBuffer(bytes));
  } finally {
    fs.closeSync(file);
  }
}

/**
 * 确保目录存在，缺失的父目录一并建出。
 *
 * 两处平台细节，都是实测踩出来的：
 *
 * 1. `fs.mkdirSync` 对**已存在**的目录抛 EEXIST，而 `fs.accessSync` 返回 boolean
 *    且不抛 —— 所以必须先探后建，不能指望 mkdir 幂等。
 * 2. `fs.mkdirSync(path, true)` 的 `recursion=true` **并不可靠地创建父目录**：
 *    实测在测试沙箱里对 `/tmp/a/b`（`/tmp/a` 不存在）抛 ENOENT
 *    "No such file or directory"。因此这里自己逐段走下去建，不依赖那个参数。
 */
export function ensureDir(path: string): void {
  if (fs.accessSync(path)) {
    return;
  }
  const segments: string[] = path.split('/');
  let current = '';
  for (const segment of segments) {
    if (segment.length === 0) {
      continue;
    }
    current += '/' + segment;
    if (!fs.accessSync(current)) {
      fs.mkdirSync(current);
    }
  }
}

/**
 * 递归删除一棵目录树；path 不存在时是 no-op。
 *
 * ## 为什么主路径是 rmdirSync 而不是「自己遍历再逐个删」
 *
 * `fs.listFileSync` 在本仓的**单测沙箱里根本不存在**（实测 `typeof` 为
 * `undefined`，调用即 "undefined is not callable"），因此任何依赖枚举子项的实现
 * 在 `hvigorw test` 下必然报错 —— 而这段逻辑正是本文件里最需要被测到的部分。
 *
 * 与此同时，`fs.rmdirSync` 在同一沙箱里实测**能直接删掉非空的嵌套目录树**
 * （建 `root/sub/a.txt` 后 `rmdirSync(root)` 成功，事后 accessSync 为 false）。
 * SDK 声明里列了 `13900032 Directory not empty` 这条错误，说明「非空能否直删」
 * 在契约上并不保证，所以下面保留了一条枚举兜底：rmdirSync 抛错时才走它，
 * 并且对 `listFileSync` 缺席同样是容错的（拿不到子项就把异常抛回调用方，
 * 而不是假装删成功 —— 静默的「删不掉」会让后续的先删后拷退化成增量覆盖，
 * 陈旧文件从此滞留）。
 */
export function removeTree(path: string): void {
  if (!fs.accessSync(path)) {
    return;
  }
  if (!fs.statSync(path).isDirectory()) {
    fs.unlinkSync(path);
    return;
  }
  try {
    fs.rmdirSync(path);
    return;
  } catch (error) {
    // 落到枚举兜底 —— 见上方注释。
  }
  const entries: string[] = listDirEntries(path);
  for (const entry of entries) {
    removeTree(path + '/' + entry);
  }
  fs.rmdirSync(path);
}

/** 列目录子项。`listFileSync` 在单测沙箱里不存在，拿不到时返回空数组。 */
function listDirEntries(path: string): string[] {
  try {
    return fs.listFileSync(path);
  } catch (error) {
    return [];
  }
}

/**
 * 把 reader 描述的一棵目录树整体落到 destDir，返回**复制的文件数**。
 *
 * 先整体删除 destDir 再重建，因此幂等：重复执行结果一致，且源树中已删除的文件
 * 不会作为残留留在目标目录中。
 *
 * 文件与子目录的区分靠 `read()` 的返回值：rawfile 的目录路径读不出内容（返回 null），
 * 于是落进递归分支。这是 rawfile API 唯一可用的判据 —— `getRawFileListSync` 对
 * 文件路径并不报错，反过来判会把空目录和文件混为一谈。
 */
export function copyTree(reader: RawfileTreeReader, srcDir: string, destDir: string): number {
  removeTree(destDir);
  return copyTreeInto(reader, srcDir, destDir);
}

function copyTreeInto(reader: RawfileTreeReader, srcDir: string, destDir: string): number {
  ensureDir(destDir);
  let copied = 0;
  const entries: string[] = reader.list(srcDir);
  for (const entry of entries) {
    const srcPath = srcDir.length === 0 ? entry : srcDir + '/' + entry;
    const destPath = destDir + '/' + entry;
    const bytes = reader.read(srcPath);
    if (bytes === null) {
      copied += copyTreeInto(reader, srcPath, destPath);
      continue;
    }
    writeBytes(destPath, bytes);
    copied++;
  }
  return copied;
}

/**
 * `copyTree` 的 Context 版薄封装：把 rawfile 下的 `rawfileDir` 整体落到沙箱 `destDir`。
 *
 * 目录路由演示（compatibility.md §13.2）需要一个**真实沙箱目录**才能演示
 * `FileDirectoryResolver` + `addAllowedFileRoot` 这条 FilePath 链路；rawfile 本身
 * 不是文件系统路径，无法直接喂给 FileDirectoryResolver。
 */
export function copyRawfileDirToSandbox(
  context: common.UIAbilityContext,
  rawfileDir: string,
  destDir: string,
): number {
  const reader: RawfileTreeReader = {
    list: (dir: string) => listRawfileEntries(context, dir),
    read: (path: string) => readRawfileBytes(context, path),
  };
  return copyTree(reader, rawfileDir, destDir);
}
