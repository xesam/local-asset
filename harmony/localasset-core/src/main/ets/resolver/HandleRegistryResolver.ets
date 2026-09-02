import {
  ResourceResolver,
  ResolverResult,
  resolverHit,
  resolverSkip,
} from '../api/ResourceResolver';
import { HandleRegistry } from '../api/HandleRegistry';
import { AssetRequest } from '../model/AssetRequest';
import { ResolveContext } from '../model/ResolveContext';
import {
  ResourceType,
  createResourceDescriptor,
} from '../model/ResourceDescriptor';

/**
 * Handle 路径的 resolver，链上永远排第一（反查 handle URI）。
 *
 * 与 Kotlin / iOS 同名类逐字段核对过，产出的 descriptor 有三个字段是**刻意置空/置零**的，
 * 不是漏填，改动前请先读 design.md §5.4：
 *
 * - `scope = null`：Handle 路径是**能力令牌模型**，持有不透明 token 即等于授权。
 *   Policy.postCheck 的 namespace/scope 门是 Registry 路径的授权手段，对 handle 必须整体跳过；
 *   一旦这里填了 scope，postCheck 会要求 descriptor.namespace 与上下文 scope 身份匹配，
 *   于是每一条 handle 请求都被拒。
 * - `ttlMillis = null`：TTL 归 HandleRegistry.resolve() 所有，判据是相对自身创建时刻的
 *   `now - createdAt >= ttl`，且已在 lookup 时惰性驱逐。此处 createdAtMillis 是占位 0，
 *   若把 record.ttlMillis 透传下去，postCheck 的**绝对时间**判据 `createdAtMillis + ttl <= now`
 *   会用「纪元 0 + ttl」跟当前时间比 —— 结果是**每一条** handle 都被判过期。
 * - `createdAtMillis = 0`：占位。handle 的真实创建时刻只存在 HandleRegistry 内部
 *   （StoredHandle.createdAtMillis），descriptor 不携带它。正因为它是占位值，
 *   上面那条 ttl 必须为 null 才自洽 —— 两者是一组，不能只改其一。
 *
 * 其余字段：`id` 取 record.fileName（**原始**文件名，非 URI 里那个净化过的段），
 * `namespace` 取请求的 namespace（即 handle registry 的 host），type 恒为 DYNAMIC。
 */
export class HandleRegistryResolver implements ResourceResolver {
  private readonly handleRegistry: HandleRegistry;

  constructor(handleRegistry: HandleRegistry) {
    this.handleRegistry = handleRegistry;
  }

  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    // resolveFromRequest 反查失败（未知或已过期）返回 null，不抛错 —— 这正是 resolver
    // 探测"这条请求归不归我管"所需的语义。过期在这一层表现为 Skip 而非 Failure。
    const record = this.handleRegistry.resolveFromRequest(request);
    if (record === null) {
      return resolverSkip();
    }
    return resolverHit(createResourceDescriptor({
      id: record.fileName,
      namespace: request.namespace,
      type: ResourceType.DYNAMIC,
      source: record.source,
      mimeType: record.mimeType,
      createdAtMillis: 0,
      ttlMillis: null,
      scope: null,
    }));
  }
}
