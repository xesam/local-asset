import {
  ResourceResolver,
  ResolverResult,
  resolverHit,
  resolverSkip,
  resolverFailure,
} from '../api/ResourceResolver';
import { ResourceRegistry } from '../api/ResourceRegistry';
import { AssetRequest } from '../model/AssetRequest';
import { ResolveContext } from '../model/ResolveContext';
import { ResourceErrorCategory } from '../error/ResourceErrorCategory';

/**
 * Registry 路径的兜底 resolver：按 id 查 ResourceRegistry（design.md §5.4）。
 *
 * 逐条核对过 Kotlin `RegistryResolver` 与 iOS 同名类：
 * 1. id 取 `request.identifier ?? request.query['id']`，identifier 优先；两者皆无 → Skip。
 * 2. lookup 的三态直接映射：hit → Hit，missing → **Skip**（把机会让给链上后续 resolver），
 *    expired → **Failure**(RESOLUTION_ERROR, 'resource expired')。
 *    missing 与 expired 的这一分歧是刻意的：查无此条是"不归我管"，过期是"归我管但已作废"，
 *    后者必须短路成失败，否则后面的 resolver 可能拿一条陈旧映射把它救回来。
 * 3. reason 字符串 'resource expired' 是跨平台契约，不要改写。
 *
 * 对比 HandleRegistryResolver：那边过期表现为 Skip，因为 resolveFromRequest 把
 * HandleRegistry 的抛错吞成 null，能力凭证不向持有方区分"未知/已过期"。
 */
export class RegistryResolver implements ResourceResolver {
  private readonly registry: ResourceRegistry;

  constructor(registry: ResourceRegistry) {
    this.registry = registry;
  }

  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    const id: string | null = request.identifier ?? request.query.get('id') ?? null;
    if (id === null) {
      return resolverSkip();
    }
    const result = this.registry.lookup(id);
    if (result.kind === 'hit') {
      return resolverHit(result.descriptor);
    }
    if (result.kind === 'expired') {
      return resolverFailure(ResourceErrorCategory.RESOLUTION_ERROR, 'resource expired');
    }
    return resolverSkip();
  }
}
