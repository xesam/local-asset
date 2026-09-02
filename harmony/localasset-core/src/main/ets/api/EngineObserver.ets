import { AssetRequest } from '../model/AssetRequest';
import { ResourceDescriptor } from '../model/ResourceDescriptor';
import { ResolverResult } from './ResourceResolver';
import { ResourceErrorCategory } from '../error/ResourceErrorCategory';

/**
 * design.md §8：引擎每次请求都要能被外部观测到——adapter 命中、resolver 顺序与决策、
 * policy 通过/拒绝、descriptor 标识、source 类型、错误阶段与类别，且不耦合平台日志。
 *
 * 下面六个 stage 字面量是跨平台契约（与 Kotlin 的 EngineObserver.STAGE_* 常量、
 * iOS 的同名常量逐字一致），不要改写拼法或大小写。
 */
export const STAGE_ADAPTER_PARSE = 'adapter_parse';
export const STAGE_POLICY_PRE = 'policy_pre';
export const STAGE_RESOLVE = 'resolve';
export const STAGE_POLICY_POST = 'policy_post';
export const STAGE_LOAD = 'load';
export const STAGE_COMPLETE = 'complete';

/**
 * Kotlin 侧此处直接放 `EngineResult.Failure`。harmony 的 EngineResult 定义在 api/LocalAssetEngine.ets，晚于本文件
 * 才出现，而 ResolverChain 现在就需要发事件，所以拆出这个只承载失败三要素的
 * 结构（类别 / 原因 / 阶段），语义与 Kotlin 的 Failure 一一对应。
 */
export interface EngineFailureInfo {
  category: ResourceErrorCategory;
  reason: string;
  stage: string | null;
}

/**
 * 只有与 stage 相关的字段会被填充。带非空 failure 的事件是终止事件；
 * 成功终止则是一条 stage === STAGE_COMPLETE 且 failure 为 null 的事件。
 *
 * 与 Kotlin 的 EngineStageEvent 相比少了 `resolver: ResourceResolver?` 字段：
 * 该字段在参考实现里只用于让观察者打印 resolver 的类名，而 ArkTS 侧拿不到稳定的
 * 运行时类名；resolverIndex 已足以定位是链上第几个 resolver。
 */
export interface EngineStageEvent {
  stage: string;
  request: AssetRequest | null;
  resolverIndex: number | null;
  resolverResult: ResolverResult | null;
  descriptor: ResourceDescriptor | null;
  failure: EngineFailureInfo | null;
}

/**
 * 契约：请求实际到达的每个 stage 至少发一次事件。引擎是同步的，事件按调用顺序
 * 在调用线程上触发；观察者不得对流水线产生副作用（事件里的 request / descriptor
 * 是快照，改它们不影响引擎行为）。
 */
export interface EngineObserver {
  onStage(event: EngineStageEvent): void;
}
