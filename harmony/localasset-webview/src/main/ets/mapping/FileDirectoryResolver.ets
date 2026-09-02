import fs from '@ohos.file.fs';
import { ResourceSource, filePathSource, normalizeAbsolutePath } from 'io.github.xesam.harmony.localasset.core';
import { BaseDirectoryResolver } from './DirectoryResolverSupport';

export interface FileDirectoryResolverOptions {
  host: string;
  pathPrefix: string;
  /** 沙箱内的根目录，如 `context.cacheDir + '/sample-pkg'`。 */
  rootDirectory: string;
}

/**
 * 把 `local-asset://host/prefix/**` 映射到沙箱文件目录。
 * 对应 Android / iOS 的同名类。
 *
 * 命中只产出 **FilePath 描述符**；能否真的读到还要过 `DefaultPolicy` 的文件根门禁，
 * 而那道门禁默认 **fail-closed**（没声明任何允许的根 = 一条 filePath 都不放行，
 * design.md §5.5）。这是刻意的：调用方必须在 Builder 上显式 `addAllowedFileRoot`。
 * 本类不做任何"预先满足 policy"的事，两层职责不混。
 *
 * ## 与 Android/iOS 的已知差异：不解析符号链接
 *
 * Android 用 `File.canonicalFile`、iOS 用 `resolvingSymlinksInPath()` 得到真实路径，
 * 于是「根下的符号链接指向根外」会被两端拒掉。`@ohos.file.fs` 没有 realpath/canonicalize
 * （core `DefaultPolicy` 的类注释里记录了完整核查过程），因此这里的包含校验是**纯词法**的，
 * 与 core 侧的规范化处于同一局限。缓解手段同样是：不要把允许的文件根设在第三方可写、
 * 可创建符号链接的目录下。
 */
export class FileDirectoryResolver extends BaseDirectoryResolver {
  private readonly rootDirectory: string;

  constructor(options: FileDirectoryResolverOptions) {
    super(options.host, options.pathPrefix);
    this.rootDirectory = options.rootDirectory.endsWith('/')
      ? options.rootDirectory.substring(0, options.rootDirectory.length - 1)
      : options.rootDirectory;
  }

  protected resolveSource(relativePath: string): ResourceSource | null {
    const target = this.rootDirectory + '/' + relativePath;
    // 纵深防御：确认目标**折叠 `..` 之后**仍落在根下。
    //
    // 参考实现（Android/iOS）在这里做的是 canonicalize + 带分隔符比前缀；本仓
    // 没有 realpath，故只能词法折叠。注意**裸 startsWith 在这里是无效防御**：
    // `/root/../../etc/passwd` 的字符串前缀与 `/root/` 完全相同，照样放行。
    // BaseDirectoryResolver 已拒掉所有 `..` 段，所以走 resolve() 时这条恒真；
    // 保留它是为了让本方法**独立成立** —— resolveSource 是 protected 扩展点，
    // 子类或直接调用者传进来的 relativePath 没经过 resolve() 那道校验。
    if (!isLexicallyWithin(target, this.rootDirectory)) {
      return null;
    }
    // fs.statSync 在路径不存在时会抛出，这一步同时充当存在性探测；不必先 accessSync
    // 再 statSync —— 目录同样能通过 accessSync，只有 statSync 才能分辨出目录 vs 普通文件，
    // 两次系统调用换不来额外信息，合并成一次。
    try {
      if (fs.statSync(target).isDirectory()) {
        return null;
      }
    } catch (error) {
      return null;
    }
    return filePathSource(target);
  }
}

/**
 * 纯词法判断 target 是否在 root 之下：折叠 `.` / `..` 段后再带分隔符比前缀。
 * `normalizeAbsolutePath` 来自 core 的 `DefaultPolicy`——同一份实现，不是同策略的
 * 两份拷贝：`resolveSource` 是 protected 扩展点，第三方子类可以绕过 `preCheck` 直接
 * 调用它，所以这里必须能独立完成折叠校验，但"独立生效"只要求可以脱离引擎单独调用，
 * 不要求另抄一份算法——复用同一个导出函数一样满足这个要求，还消除了两处手改不同步的风险。
 */
function isLexicallyWithin(target: string, root: string): boolean {
  const normalizedTarget = normalizeAbsolutePath(target);
  const normalizedRoot = normalizeAbsolutePath(root);
  if (normalizedTarget === null || normalizedRoot === null) {
    return false;
  }
  // 带分隔符比较，理由同 matchesPrefix：裸 startsWith 会把 /root-evil 判成 /root 之下。
  return normalizedTarget === normalizedRoot || normalizedTarget.startsWith(normalizedRoot + '/');
}
