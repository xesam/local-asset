export enum ResourceType {
  STATIC = 'STATIC',
  DYNAMIC = 'DYNAMIC',
}

export enum ResourceScope {
  ENGINE = 'ENGINE',
  PAGE = 'PAGE',
  SESSION = 'SESSION',
}

/**
 * 注意：Kotlin 侧 ResourceSource.Bytes 显式重写了 equals/hashCode，因为 ByteArray
 * 默认是引用相等。ArkTS 的 interface 没有等价机制——BytesSource（以及下面的
 * ResourceData、ResourceHandle、ResourceHandleRecord）一律是引用相等：
 * 不要拿它们当 Map 的 key，也不要用 === 比较字节内容（那只比对象身份）。
 * 需要比内容时请显式逐字节比较。
 */
export interface BytesSource {
  kind: 'bytes';
  value: Uint8Array;
}

export interface FilePathSource {
  kind: 'filePath';
  value: string;
}

/**
 * Kotlin sealed interface 的 ArkTS 等价。design.md §4.4 只要求 Bytes 与 FilePath 两种来源；
 * Stream 变体是 Android/iOS 的平台内优化，harmony 侧不实现（见 `docs/design.md` §9.3）。
 */
export type ResourceSource = BytesSource | FilePathSource;

export function bytesSource(value: Uint8Array): BytesSource {
  return { kind: 'bytes', value: value };
}

export function filePathSource(value: string): FilePathSource {
  return { kind: 'filePath', value: value };
}

export interface ResourceDescriptor {
  id: string;
  namespace: string;
  type: ResourceType;
  source: ResourceSource;
  mimeType: string | null;
  createdAtMillis: number;
  ttlMillis: number | null;
  scope: ResourceScope | null;
}

export interface ResourceDescriptorParams {
  id: string;
  namespace: string;
  type: ResourceType;
  source: ResourceSource;
  mimeType?: string | null;
  createdAtMillis: number;
  ttlMillis?: number | null;
  scope?: ResourceScope | null;
}

export function createResourceDescriptor(params: ResourceDescriptorParams): ResourceDescriptor {
  return {
    id: params.id,
    namespace: params.namespace,
    type: params.type,
    source: params.source,
    mimeType: params.mimeType ?? null,
    createdAtMillis: params.createdAtMillis,
    ttlMillis: params.ttlMillis ?? null,
    scope: params.scope ?? null,
  };
}
