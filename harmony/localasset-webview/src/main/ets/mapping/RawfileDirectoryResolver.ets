import { ResourceSource, bytesSource } from 'io.github.xesam.harmony.localasset.core';
import { BaseDirectoryResolver } from './DirectoryResolverSupport';

export interface RawfileDirectoryResolverOptions {
  host: string;
  pathPrefix: string;
  /** rawfile 下的子目录，如 'demo/static'。留空表示 rawfile 根。 */
  rawfileDirectory?: string;
  /**
   * 读取 rawfile 的函数，读不到时返回 null（或抛异常，两者都收敛成 Skip）。
   *
   * 之所以注入而不是直接收 Context：`resourceManager` 只能从真实应用 Context 取得，
   * 本地单元测试沙箱里没有 Context，注入后才能用替身覆盖 —— 与 Android
   * `AssetDirectoryResolver` 注入 `openAsset: (String) -> InputStream` 同一手法、同一理由。
   * sample 侧传 `(p) => context.resourceManager.getRawFileContentSync(p)`。
   */
  readRawfile: (path: string) => Uint8Array | null;
}

/**
 * 把 `local-asset://host/prefix/**` 映射到 `resources/rawfile/` 下的静态资源。
 * 对应 Android 的 `AssetDirectoryResolver` 与 iOS 的 `BundleDirectoryResolver`。
 *
 * 与那两端的一处**已知差异**：它们产出 Stream 来源，资源字节不驻留内存；harmony 侧
 * core 的 `ResourceSource` 只有 Bytes / FilePath 两种变体（design.md §4.4，Stream 是
 * 平台内优化），且 `getRawFileContentSync` 本身就一次性返回整个 Uint8Array，
 * 因此这里产出 Bytes 来源 —— 大文件会整份读进内存。
 */
export class RawfileDirectoryResolver extends BaseDirectoryResolver {
  private readonly rawfileDirectory: string;
  private readonly readRawfile: (path: string) => Uint8Array | null;

  constructor(options: RawfileDirectoryResolverOptions) {
    super(options.host, options.pathPrefix);
    let directory = options.rawfileDirectory ?? '';
    while (directory.startsWith('/')) {
      directory = directory.substring(1);
    }
    while (directory.endsWith('/')) {
      directory = directory.substring(0, directory.length - 1);
    }
    this.rawfileDirectory = directory;
    this.readRawfile = options.readRawfile;
  }

  protected resolveSource(relativePath: string): ResourceSource | null {
    const rawfilePath = this.rawfileDirectory.length === 0
      ? relativePath
      : this.rawfileDirectory + '/' + relativePath;
    let bytes: Uint8Array | null = null;
    try {
      bytes = this.readRawfile(rawfilePath);
    } catch (error) {
      // rawfile 缺失时 resourceManager 抛错而非返回 null。收敛成 Skip，让失败停在
      // RESOLVE 阶段（与 Android/iOS 的错误阶段语义一致）；放任异常穿透 ResolverChain
      // 会把一次"资源不存在"变成另一个 category。
      return null;
    }
    if (bytes === null) {
      return null;
    }
    return bytesSource(bytes);
  }
}
