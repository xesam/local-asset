import fs from '@ohos.file.fs';
import { ResourceDescriptor, ResourceType } from '../model/ResourceDescriptor';

/**
 * 已解析资源的缓存响应头，由平台响应层附加到响应上。
 * `cacheControl` 即 `Cache-Control`，`etag` 即 `ETag`。
 */
export interface CacheDecision {
  cacheControl: string;
  etag: string;
}

export const DEFAULT_MAX_AGE_SECONDS = 86400;

/**
 * 平台无关的缓存策略，保证三端对同一 descriptor 下发**逐字节相同**的响应头
 * （design.md §7；跨端契约由 docs/compatibility-fixtures/cache-headers.json 钉住）。
 * 与 Kotlin `ResourceCachePolicy` / iOS 同名类型逐行核对过。
 *
 * - STATIC 视为不可变的随包资源 → 可缓存，带 `max-age`；
 *   DYNAMIC 由 registry 注册、每次解析都可能不同 → 一律 `no-store`。
 * - ETag 由 `descriptor.id` 加一个**反映内容**的廉价信号构成：既在多次解析间稳定，
 *   又能在底层字节变化时改变。`filePath` 取文件 mtime，`bytes` 取字节长度。
 *
 * 与 Kotlin/iOS 的**已知差异**：两端还有第三个分支 `Stream` → 弱 etag `W/"<id>"`。
 * harmony 的 ResourceSource 刻意只有 bytes / filePath 两个变体（见 model/ResourceDescriptor.ets
 * 与 `docs/design.md` §9.3），因此本平台没有该分支，共享 fixture 里的 `static-stream-weak-etag`
 * 用例对本平台不适用（CompatibilityFixture.test.ets 中已显式说明并跳过）。
 *
 * 刻意**不**实现条件请求（304）：默认响应构建器一律返回 200 并附上这些头，
 * 从不产生 304。ETag 仍作为元数据下发；真正省流量的是 `max-age` 窗口内
 * WebView 直接吃本地缓存、根本不发起校验。
 *
 * mtime 的取用：Kotlin 用 `File(path).lastModified()`，本实现用 `fs.statSync(path).mtime`。
 * ⚠️ 单位差异已核实：`@ohos.file.fs` 的 `stat.mtime` 是**秒**（Kotlin 的 lastModified 是毫秒）。
 * 这不影响跨端契约 —— cache-headers.json 里带 etag 断言的用例全是 bytes 来源，
 * filePath 的 etag 只要求"随内容变化而变化"，各端取值不必相等。
 */
export function decideCache(
  descriptor: ResourceDescriptor,
  maxAgeSeconds: number = DEFAULT_MAX_AGE_SECONDS,
): CacheDecision {
  const cacheControl = descriptor.type === ResourceType.STATIC
    ? 'public, max-age=' + maxAgeSeconds.toString()
    : 'no-store';
  return { cacheControl: cacheControl, etag: computeEtag(descriptor) };
}

function computeEtag(descriptor: ResourceDescriptor): string {
  const source = descriptor.source;
  if (source.kind === 'bytes') {
    return '"' + descriptor.id + '-' + source.value.length.toString() + '"';
  }
  // 计算响应头绝不能把请求打挂：文件不存在/不可读时退化成 0，而不是向上抛。
  // 对齐 Kotlin —— `File(path).lastModified()` 在文件缺失时同样返回 0 而非抛异常。
  let lastModified = 0;
  try {
    lastModified = fs.statSync(source.value).mtime;
  } catch (error) {
    lastModified = 0;
  }
  return '"' + descriptor.id + '-' + lastModified.toString() + '"';
}
