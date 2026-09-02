import { ResourceDescriptor } from '../model/ResourceDescriptor';

export interface RegistryHit {
  kind: 'hit';
  descriptor: ResourceDescriptor;
}

export interface RegistryMissing {
  kind: 'missing';
}

export interface RegistryExpired {
  kind: 'expired';
}

/**
 * Kotlin 侧是 `sealed interface RegistryLookupResult { data class Hit; data object Missing;
 * data object Expired }`，iOS 侧是 `enum RegistryLookupResult`。ArkTS 用 tagged union 等价表达；
 * `kind` 的三个字面量 'hit' / 'missing' / 'expired' 是跨平台契约，不要改写成别的拼法或大写。
 *
 * lookup 返回三态而不抛错：missing / expired 是 resolver 探测「这个请求归不归我管」的
 * 日常分支，不是异常情况。对比 HandleRegistry.resolve —— 那边解析失败会抛错，因为交还给
 * 原生侧的 Handle-Backed URI 更接近凭据，解析不出来属于异常而非正常控制流。
 */
export type RegistryLookupResult = RegistryHit | RegistryMissing | RegistryExpired;

export function registryHit(descriptor: ResourceDescriptor): RegistryHit {
  return { kind: 'hit', descriptor: descriptor };
}

/**
 * 注意：Kotlin 侧 RegistryLookupResult.Missing / Expired 是 `data object`（进程内单例），
 * iOS 侧是无 payload 的 `case .missing` / `.expired`；而这里每次调用都返回一个**新对象**，
 * 对象身份各不相同。因此消费者必须按 `result.kind === 'missing'` 判别，绝不能用 `===`/`==`
 * 与某个 Missing 实例比较——那只比对象身份，对本实现恒为 false。Hit 同理。
 * （与 api/ResourceResolver.ets 中 resolverSkip 的注记同源，同一条房规。）
 */
export function registryMissing(): RegistryMissing {
  return { kind: 'missing' };
}

export function registryExpired(): RegistryExpired {
  return { kind: 'expired' };
}

/**
 * 存放调用方注册的 ResourceDescriptor，按其自身 id 索引，由 ResolverChain 中的
 * RegistryResolver 查询。
 *
 * 线程模型：registry 的状态是**实例内的**，且假定只在单个事件循环（单个 VM）内访问。
 * ArkTS 的 Worker 各持独立 VM，普通对象无法按引用跨 VM 共享 —— 在 UI 线程注册的资源
 * 在 Worker 里查不到，重复 id 检查也不跨 VM。所以请让 engine 与它的 registry 同线程使用；
 * 需要跨 Worker 时应显式传递数据，而不是共享 registry 实例。
 * （对比：Kotlin 接口文档对线程只字未提，但其实现由 ConcurrentHashMap 兜底；
 *   iOS 由 NSLock 兜底。本平台没有等价兜底，故把约束提到接口层写明。）
 */
export interface ResourceRegistry {
  register(descriptor: ResourceDescriptor): void;

  lookup(id: string): RegistryLookupResult;

  remove(id: string): void;

  cleanup(nowMillis?: number): void;
}
