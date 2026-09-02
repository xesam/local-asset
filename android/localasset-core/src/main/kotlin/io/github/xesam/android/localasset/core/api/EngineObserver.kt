package io.github.xesam.android.localasset.core.api

import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResourceDescriptor

/**
 * Observes the engine pipeline as a single request flows through it. Wire one in via
 * [LocalAsset.Builder.observer] to get structured visibility into every stage — adapter parse,
 * policy pre/post checks, each resolver's decision, the load step, and the terminal outcome —
 * without coupling to platform logging (design.md §8).
 *
 * The contract is "at least one event per stage the request actually reached"; observers must be
 * tolerant of reentrancy (the engine is synchronous, so events fire in call order on the calling
 * thread) and side-effect-free with respect to the pipeline (mutating [AssetRequest] /
 * [ResourceDescriptor] from an observer has no effect — the values are snapshots).
 *
 * Termination rule: an event carrying a non-null [EngineStageEvent.failure] is terminal — the
 * engine returns that failure and emits nothing further for the request. A terminal success is
 * signalled by a single event with [EngineStageEvent.stage] == [STAGE_COMPLETE] and a null failure.
 */
interface EngineObserver {
    fun onStage(event: EngineStageEvent)

    companion object {
        /** Stage name emitted right after a scheme adapter parses the URL into an [AssetRequest]. */
        const val STAGE_ADAPTER_PARSE = "adapter_parse"
        const val STAGE_POLICY_PRE = "policy_pre"
        const val STAGE_RESOLVE = "resolve"
        const val STAGE_POLICY_POST = "policy_post"
        const val STAGE_LOAD = "load"
        const val STAGE_COMPLETE = "complete"
    }
}

/**
 * A single pipeline event. Only the fields relevant to [stage] are populated:
 *
 * - [STAGE_ADAPTER_PARSE] / [STAGE_POLICY_PRE] / [STAGE_POLICY_POST] / [STAGE_LOAD] / [STAGE_COMPLETE]:
 *   [request] is always set; [descriptor] is set once a descriptor is known (postCheck, load,
 *   complete); [failure] is set when this stage is the terminal failure point.
 * - [STAGE_RESOLVE]: emitted once per resolver in chain order, carrying [resolverIndex] /
 *   [resolver] / [resolverResult]; when the whole chain skips, the engine emits one final
 *   `resolve` event with [failure] set ("resource not found") and no resolver fields.
 *
 * [request] is null only for an [STAGE_ADAPTER_PARSE] failure that occurred before the URL could be
 * parsed into an [AssetRequest]; every other stage carries the request snapshot.
 */
data class EngineStageEvent(
    val stage: String,
    val request: AssetRequest?,
    val resolverIndex: Int? = null,
    val resolver: ResourceResolver? = null,
    val resolverResult: ResolverResult? = null,
    val descriptor: ResourceDescriptor? = null,
    val failure: EngineResult.Failure? = null,
) {
    val isTerminal: Boolean get() = failure != null || stage == EngineObserver.STAGE_COMPLETE
}
