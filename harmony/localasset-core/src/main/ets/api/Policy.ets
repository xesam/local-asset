import { AssetRequest } from '../model/AssetRequest';
import { ResolveContext } from '../model/ResolveContext';
import { ResourceDescriptor } from '../model/ResourceDescriptor';

/**
 * design.md §3.2 / §5.1：两阶段强制校验，不可绕过。违规时抛 ResourceException。
 *
 * preCheck 在 ResolverChain 之前（请求级），postCheck 在命中 descriptor 之后、Loader 之前
 * （资源级）。两个方法都是「通过即静默返回」，只用异常表达拒绝 —— 与 Kotlin `Policy`
 * 接口（返回 Unit，抛 ResourceException）以及 iOS 同名协议（throws）语义一致。
 */
export interface Policy {
  preCheck(request: AssetRequest, context: ResolveContext): void;

  postCheck(request: AssetRequest, descriptor: ResourceDescriptor, context: ResolveContext): void;
}
