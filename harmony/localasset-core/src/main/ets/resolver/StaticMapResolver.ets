import {
  ResourceResolver,
  ResolverResult,
  resolverHit,
  resolverSkip,
} from '../api/ResourceResolver';
import { AssetRequest } from '../model/AssetRequest';
import { ResolveContext } from '../model/ResolveContext';
import { ResourceDescriptor } from '../model/ResourceDescriptor';

/**
 * 静态映射 resolver：key 形如 `"<namespace>:<path>"`，命中即原样返回映射里的 descriptor。
 *
 * 与 Kotlin / iOS 同名类一致的两点：
 * 1. key 必须带 namespace 前缀 —— 只按 path 匹配会让不同 namespace 互相读到对方的资源。
 * 2. descriptor **不加工**：scope / ttlMillis / createdAtMillis 全部照搬调用方给的值，
 *    走 Registry 路径的 namespace/scope 安全模型，正常接受 postCheck 的全部门禁。
 *    （与 HandleRegistryResolver 的刻意置空形成对照，见 design.md §5.4。）
 *
 * path 为 null 时 Skip：AssetRequest 保证 identifier 与 path 至少一个非空，
 * 但只有 identifier 的请求在这张表里没有可用的 key。
 */
export class StaticMapResolver implements ResourceResolver {
  private readonly mappings: Map<string, ResourceDescriptor>;

  constructor(mappings: Map<string, ResourceDescriptor>) {
    this.mappings = mappings;
  }

  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    const path = request.path;
    if (path === null) {
      return resolverSkip();
    }
    const descriptor = this.mappings.get(request.namespace + ':' + path);
    if (descriptor === undefined) {
      return resolverSkip();
    }
    return resolverHit(descriptor);
  }
}
