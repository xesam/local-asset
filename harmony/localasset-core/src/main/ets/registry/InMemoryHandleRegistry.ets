import { HandleRegistry, reconstructUriFromRequest, DEFAULT_HANDLE_HOST } from '../api/HandleRegistry';
import { AssetRequest } from '../model/AssetRequest';
import { ResourceHandle, ResourceHandleRecord } from '../model/ResourceHandle';
import { ResourceErrorCategory } from '../error/ResourceErrorCategory';
import { ResourceException } from '../error/ResourceException';
import { generateUuidV4 } from '../internal/Uuid';

interface StoredHandle {
  record: ResourceHandleRecord;
  createdAtMillis: number;
}

/**
 * 对齐 Kotlin `InMemoryHandleRegistry`（ConcurrentHashMap + UUID.randomUUID）与
 * iOS 同名类（Dictionary + NSLock + UUID()）。逐条核对过的行为：
 *
 * 1. URI 形态 `local-asset://<host>/<prefix>/<token>/<safeFileName>`；`safeFileName` 只影响 URI，
 *    `record.fileName` 保留调用方给的原名（两端皆然）。
 * 2. 文件名净化正则 `[^A-Za-z0-9._-]` → `_`，顺带把 `/` 也换掉，所以文件名无法伪造出额外路径段。
 * 3. TTL 判据是 `now - createdAt >= ttl`（闭区间，>= 不是 >），且**读时惰性驱逐**：
 *    Kotlin 用 `items.compute{...}` 返回 null 来删除条目，iOS 用 `items.removeValue`。
 *    这与 ResourceRegistry.lookup 刻意不对称 —— 那边只报告状态、留给 cleanup 删。
 * 4. `createdAtMillis` 取注册那一刻的 nowProvider()，不是构造期快照，也不是常量 0。
 * 5. 未知与已过期返回**同一条**错误信息 `Unknown or expired resourceUri: <uri>`：
 *    不向持凭证方泄露「这条 URI 曾经存在过」。
 * 6. cleanup 判据 `createdAt + ttl <= nowMillis`，与 resolve 的 `now - createdAt >= ttl` 等价。
 *
 * 差异：Kotlin/iOS 有并发保护（ConcurrentHashMap / NSLock），本实现用裸 Map。
 * ArkTS 每个 Worker 是独立 VM，同一事件循环内不存在数据竞争，无需加锁；
 * 但同样地，裸 Map 无法跨 Worker 按引用共享 —— 在 UI 线程注册的 handle 在 Worker 里
 * 解析不到（抛 RESOLUTION_ERROR）。registry 实例只服务于创建它的那个 VM。
 * （与 InMemoryResourceRegistry 同一条房规。）
 *
 * Token 熵：`generateUuidV4()`（`internal/Uuid.ets`）优先使用系统 CSPRNG
 * （`@ohos.security.cryptoFramework`），在沙箱中回退到 `Math.random()`。真机上 token 不可
 * 猜测性对齐 Kotlin `UUID.randomUUID()` 与 iOS `UUID()`。
 */
export class InMemoryHandleRegistry implements HandleRegistry {
  private readonly items: Map<string, StoredHandle> = new Map<string, StoredHandle>();
  private readonly host: string;
  private readonly pathPrefix: string;
  private readonly nowProvider: () => number;

  constructor(
    host: string = DEFAULT_HANDLE_HOST,
    pathPrefix: string = '/handles',
    nowProvider: () => number = () => Date.now(),
  ) {
    this.host = host;
    this.pathPrefix = pathPrefix;
    this.nowProvider = nowProvider;
  }

  register(handle: ResourceHandle): string {
    // 净化只作用于 URI 段；record 保留原始 fileName（对齐 Kotlin/iOS）。
    const safeFileName = handle.fileName.replace(/[^A-Za-z0-9._-]/g, '_');
    const resourceUri = this.buildUri(generateUuidV4(), safeFileName);
    const source = handle.source;
    // bytes 来源才知道 size；filePath 注册时不读盘，size 留 null（对齐 Kotlin/iOS）。
    const size: number | null = source.kind === 'bytes' ? source.value.length : null;
    const record: ResourceHandleRecord = {
      resourceUri: resourceUri,
      source: handle.source,
      fileName: handle.fileName,
      mimeType: handle.mimeType,
      size: size,
      metadata: handle.metadata,
      ttlMillis: handle.ttlMillis,
    };
    const stored: StoredHandle = {
      record: record,
      createdAtMillis: this.nowProvider(),
    };
    this.items.set(resourceUri, stored);
    return resourceUri;
  }

  resolve(resourceUri: string): ResourceHandleRecord {
    const stored = this.items.get(resourceUri);
    if (stored === undefined) {
      throw this.unknownOrExpired(resourceUri);
    }
    const ttlMillis = stored.record.ttlMillis;
    if (ttlMillis !== null && this.nowProvider() - stored.createdAtMillis >= ttlMillis) {
      // 读时惰性驱逐：立刻移除，之后一律视为未知（即使时钟被回拨也不会复活）。
      this.items.delete(resourceUri);
      throw this.unknownOrExpired(resourceUri);
    }
    return stored.record;
  }

  resolveFromRequest(request: AssetRequest): ResourceHandleRecord | null {
    const uri = reconstructUriFromRequest(request);
    try {
      return this.resolve(uri);
    } catch (error) {
      // resolver 探测路径要的是 miss 分支而非异常；能力凭证的"抛错"语义只留给直接 resolve()。
      return null;
    }
  }

  remove(resourceUri: string): void {
    this.items.delete(resourceUri);
  }

  cleanup(nowMillis: number = Date.now()): void {
    // 先收集再删除：遍历中直接 delete 会改动正在迭代的 Map。
    const doomed: string[] = [];
    this.items.forEach((stored: StoredHandle, key: string) => {
      const ttlMillis = stored.record.ttlMillis;
      if (ttlMillis !== null && stored.createdAtMillis + ttlMillis <= nowMillis) {
        doomed.push(key);
      }
    });
    for (const key of doomed) {
      this.items.delete(key);
    }
  }

  /** 未知与过期共用同一条消息，避免泄露"这条 URI 曾存在"。 */
  private unknownOrExpired(resourceUri: string): ResourceException {
    return new ResourceException(
      ResourceErrorCategory.RESOLUTION_ERROR,
      'Unknown or expired resourceUri: ' + resourceUri,
    );
  }

  private buildUri(token: string, fileName: string): string {
    // Kotlin: pathPrefix.trim('/').takeIf { it.isNotBlank() } ?: "handles"
    // —— 两端斜杠全剥，剥完为空白则回落 'handles'。这里用 isBlank 语义（含纯空白），
    // 与 Kotlin 一致；iOS 只判 isEmpty，纯空白前缀那一例两端本就有分歧，取更安全的一侧。
    let normalizedPrefix = this.pathPrefix.replace(/^\/+/, '').replace(/\/+$/, '');
    if (normalizedPrefix.trim().length === 0) {
      normalizedPrefix = 'handles';
    }
    return 'local-asset://' + this.host + '/' + normalizedPrefix + '/' + token + '/' + fileName;
  }
}
