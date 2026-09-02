import { ResourceSource } from './ResourceDescriptor';

/**
 * 引用相等警告：Kotlin 侧 ResourceHandle / ResourceHandleRecord 都重写了
 * equals/hashCode 来按内容比较 ByteArray；ArkTS interface 无此机制。这两个类型
 * 一律是引用相等——不要当 Map key，也不要用 === 比较字节内容。
 * registry 若要做内容去重，必须显式逐字节比较或先算摘要。
 */

/**
 * Handle 现在携带 `source`（内存 `bytes` 或磁盘 `filePath`）而非永远缓冲 bytes：
 * 一个下载到磁盘的大文件可以先不读进内存，就暴露成一个可吊销、会过期的 capability。
 * filePath handle 仍靠不透明 token 授权；文件根校验在 postCheck（与 Registry 路径共享），
 * 所以路径必须落在 `addAllowedFileRoot` 声明的根下。
 */
export interface ResourceHandle {
  source: ResourceSource;
  fileName: string;
  mimeType: string;
  metadata: Map<string, string>;
  ttlMillis: number | null;
}

export interface ResourceHandleParams {
  source: ResourceSource;
  fileName: string;
  mimeType: string;
  metadata?: Map<string, string>;
  ttlMillis?: number | null;
}

export function createResourceHandle(params: ResourceHandleParams): ResourceHandle {
  return {
    source: params.source,
    fileName: params.fileName,
    mimeType: params.mimeType,
    metadata: params.metadata ?? new Map<string, string>(),
    ttlMillis: params.ttlMillis ?? null,
  };
}

export interface ResourceHandleRecord {
  resourceUri: string;
  source: ResourceSource;
  fileName: string;
  mimeType: string;
  /** 非 bytes 来源（filePath）时为 null：注册时不探查文件，size 未知。bytes 来源时为字节数。 */
  size: number | null;
  metadata: Map<string, string>;
  ttlMillis: number | null;
}
