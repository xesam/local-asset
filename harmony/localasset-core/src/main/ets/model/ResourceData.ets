/**
 * 引用相等警告：Kotlin 侧 ResourceData.Bytes 重写了 equals/hashCode 以按内容比较
 * ByteArray；ArkTS interface 无此机制。本类型是引用相等——不要当 Map key，
 * 也不要用 === 判断字节内容是否相同。
 */
export interface ResourceData {
  kind: 'bytes';
  bytes: Uint8Array;
  mimeType: string | null;
}

export function bytesData(bytes: Uint8Array, mimeType: string | null): ResourceData {
  return { kind: 'bytes', bytes: bytes, mimeType: mimeType };
}
