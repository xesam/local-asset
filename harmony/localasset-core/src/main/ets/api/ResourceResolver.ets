import { AssetRequest } from '../model/AssetRequest';
import { ResolveContext } from '../model/ResolveContext';
import { ResourceDescriptor } from '../model/ResourceDescriptor';
import { ResourceErrorCategory } from '../error/ResourceErrorCategory';

/**
 * Kotlin 侧是 `sealed interface ResolverResult { data class Hit; data object Skip; data class Failure }`。
 * ArkTS 没有 sealed class，用 tagged union 等价表达；`kind` 的三个字面量
 * 'hit' / 'skip' / 'failure' 是跨平台契约，不要改写成别的拼法或大写。
 */
export interface ResolverHit {
  kind: 'hit';
  descriptor: ResourceDescriptor;
}

export interface ResolverSkip {
  kind: 'skip';
}

export interface ResolverFailure {
  kind: 'failure';
  category: ResourceErrorCategory;
  reason: string;
}

export type ResolverResult = ResolverHit | ResolverSkip | ResolverFailure;

export function resolverHit(descriptor: ResourceDescriptor): ResolverHit {
  return { kind: 'hit', descriptor: descriptor };
}

/**
 * 注意：Kotlin 侧 ResolverResult.Skip 是 `data object`（进程内单例），iOS 侧是无
 * payload 的 `case .skip`；而这里每次调用都返回一个**新对象**，对象身份各不相同。
 * 因此消费者必须按 `result.kind === 'skip'` 判别，绝不能用 `===`/`==` 与某个
 * Skip 实例比较——那只比对象身份，对本实现恒为 false。
 * Hit / Failure 同理：判别一律走 `kind`，不要比较实例。
 * （已核对 Android 与 iOS 参考实现：两端消费者全部按类型/case 派发，
 *   无任何对 Skip 的身份或相等比较，故此差异不影响跨平台行为。）
 */
export function resolverSkip(): ResolverSkip {
  return { kind: 'skip' };
}

export function resolverFailure(category: ResourceErrorCategory, reason: string): ResolverFailure {
  return { kind: 'failure', category: category, reason: reason };
}

/**
 * 对应 Kotlin 的 `fun interface ResourceResolver`。ArkTS 无 SAM 转换，
 * 调用方必须显式 `class X implements ResourceResolver`，不能直接传 lambda。
 */
export interface ResourceResolver {
  resolve(request: AssetRequest, context: ResolveContext): ResolverResult;
}
