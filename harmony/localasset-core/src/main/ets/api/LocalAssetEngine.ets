import { AssetRequest } from '../model/AssetRequest';
import { ResolveContext } from '../model/ResolveContext';
import { ResourceData } from '../model/ResourceData';
import { ResourceDescriptor } from '../model/ResourceDescriptor';
import { ResourceErrorCategory } from '../error/ResourceErrorCategory';

export interface EngineSuccess {
  kind: 'success';
  descriptor: ResourceDescriptor;
  data: ResourceData;
}

/**
 * ⚠️ 命名与 iOS 交叉，跨端对照时务必注意：
 *   harmony `EngineFailure`     ≡ iOS `EngineResult.failure`（带 kind 判别子的联合成员）
 *   harmony `EngineFailureInfo` ≡ iOS `EngineFailure`（观测事件用的三字段结构）
 *
 * 两者**不要合并**。iOS 与 Kotlin 各自独立做过同样选择：iOS 明确定义了独立的
 * `EngineFailure` struct 供 observer 使用（EngineObserver.swift:15），与 `EngineResult.failure`
 * 分开；Kotlin 之所以能直接复用 `EngineResult.Failure`，是因为它在 sealed 层级里是个子类型，
 * 不需要携带 `kind` 判别子。harmony 属于 iOS 那种情形：若把 `EngineStageEvent.failure` 改成
 * 本类型，每次构造观测事件都要塞一个在该语境下毫无意义的 `kind: 'failure'`——那是把联合标签
 * 引进了一个根本没有联合的地方。DefaultLocalAssetEngine 的 emit 辅助函数把它投影成三字段
 * 结构，正是有意的接缝。
 */
export interface EngineFailure {
  kind: 'failure';
  category: ResourceErrorCategory;
  reason: string;
  stage: string | null;
}

export type EngineResult = EngineSuccess | EngineFailure;

export function engineSuccess(descriptor: ResourceDescriptor, data: ResourceData): EngineSuccess {
  return { kind: 'success', descriptor: descriptor, data: data };
}

export function engineFailure(
  category: ResourceErrorCategory,
  reason: string,
  stage: string | null,
): EngineFailure {
  return { kind: 'failure', category: category, reason: reason, stage: stage };
}

/**
 * ArkTS 不支持方法重载，所以 Kotlin/Swift 的两个 resolve 重载在这里拆成两个方法名。
 * 名字是外部契约：webview 桥与 `LocalAssetBuilder` 都按 resolveUrl 调用。
 */
export interface LocalAssetEngine {
  resolveUrl(url: string, context?: ResolveContext): EngineResult;

  resolveRequest(request: AssetRequest, context?: ResolveContext): EngineResult;
}
