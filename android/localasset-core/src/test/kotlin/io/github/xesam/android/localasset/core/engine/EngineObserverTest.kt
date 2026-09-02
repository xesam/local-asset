package io.github.xesam.android.localasset.core.engine

import io.github.xesam.android.localasset.core.api.EngineObserver
import io.github.xesam.android.localasset.core.api.EngineResult
import io.github.xesam.android.localasset.core.api.EngineStageEvent
import io.github.xesam.android.localasset.core.api.LocalAsset
import io.github.xesam.android.localasset.core.api.Policy
import io.github.xesam.android.localasset.core.api.ResolverResult
import io.github.xesam.android.localasset.core.api.ResourceResolver
import io.github.xesam.android.localasset.core.api.TestFixtures
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.internal.ResolverChain
import io.github.xesam.android.localasset.core.loader.BytesResourceLoader
import io.github.xesam.android.localasset.core.loader.CompositeResourceLoader
import io.github.xesam.android.localasset.core.loader.FileResourceLoader
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.policy.DefaultPolicy
import io.github.xesam.android.localasset.core.registry.InMemoryResourceRegistry
import io.github.xesam.android.localasset.core.resolver.RegistryResolver
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class EngineObserverTest {
    private class CapturingObserver : EngineObserver {
        val events = mutableListOf<EngineStageEvent>()
        override fun onStage(event: EngineStageEvent) {
            events += event
        }
    }

    private fun engine(observer: EngineObserver, resolvers: List<ResourceResolver>): DefaultLocalAssetEngine =
        DefaultLocalAssetEngine(
            adapters = listOf(DefaultLocalAssetSchemeAdapter()),
            resolverChain = ResolverChain(resolvers),
            policy = DefaultPolicy(),
            loader = CompositeResourceLoader(listOf(BytesResourceLoader(), FileResourceLoader())),
            observer = observer,
        )

    @Test
    fun success_path_emits_parse_pre_resolve_post_load_complete() {
        val registry = InMemoryResourceRegistry()
        registry.register(
            TestFixtures.resourceDescriptor(
                id = "logo",
                namespace = "image",
                bytes = "hello".encodeToByteArray(),
                mimeType = "text/plain",
            ),
        )
        val observer = CapturingObserver()
        val result = engine(observer, listOf(RegistryResolver(registry)))
            .resolve("local-asset://image/logo")

        assertTrue(result is EngineResult.Success)
        val stages = observer.events.map { it.stage }
        assertEquals(
            listOf("adapter_parse", "policy_pre", "resolve", "policy_post", "load", "complete"),
            stages,
        )
        val resolveEvent = observer.events.single { it.stage == "resolve" }
        assertEquals(0, resolveEvent.resolverIndex)
        assertTrue(resolveEvent.resolverResult is ResolverResult.Hit)
        assertEquals("logo", resolveEvent.descriptor?.id)
        // No failure event on the happy path.
        assertTrue(observer.events.none { it.failure != null })
        assertEquals("complete", observer.events.last().stage)
    }

    @Test
    fun precheck_failure_emits_terminal_failure_event() {
        val rejectingPolicy = object : Policy {
            override fun preCheck(request: AssetRequest, context: ResolveContext) {
                throw ResourceException(ResourceErrorCategory.SECURITY_ERROR, "blocked", stage = "policy_pre")
            }
            override fun postCheck(request: AssetRequest, descriptor: ResourceDescriptor, context: ResolveContext) {}
        }
        val observer = CapturingObserver()
        val engine = DefaultLocalAssetEngine(
            adapters = listOf(DefaultLocalAssetSchemeAdapter()),
            resolverChain = ResolverChain(emptyList()),
            policy = rejectingPolicy,
            loader = CompositeResourceLoader(listOf(BytesResourceLoader())),
            observer = observer,
        )

        val result = engine.resolve("local-asset://demo/logo")

        assertTrue(result is EngineResult.Failure)
        assertEquals(ResourceErrorCategory.SECURITY_ERROR, result.category)
        val preEvent = observer.events.last { it.stage == "policy_pre" }
        assertNotNull(preEvent.failure)
        assertEquals("policy_pre", preEvent.failure?.stage)
        // Terminal: nothing after the failed pre stage.
        assertTrue(observer.events.none { it.stage == "resolve" || it.stage == "complete" })
    }

    @Test
    fun not_found_emits_resolve_skip_then_resolve_failure() {
        val observer = CapturingObserver()
        val result = engine(observer, listOf(RegistryResolver(InMemoryResourceRegistry())))
            .resolve("local-asset://demo/missing")

        assertTrue(result is EngineResult.Failure)
        assertEquals(ResourceErrorCategory.RESOLUTION_ERROR, result.category)
        // The single resolver skipped, then the engine emitted a terminal resolve failure.
        val resolveEvents = observer.events.filter { it.stage == "resolve" }
        assertEquals(2, resolveEvents.size)
        assertTrue(resolveEvents[0].resolverResult is ResolverResult.Skip)
        assertNull(resolveEvents[0].failure)
        assertNotNull(resolveEvents[1].failure)
        assertEquals("resource not found", resolveEvents[1].failure?.reason)
    }

    @Test
    fun parse_failure_emits_terminal_parse_event_with_null_request() {
        val observer = CapturingObserver()
        val result = engine(observer, emptyList()).resolve("local-asset:///invalid")

        assertTrue(result is EngineResult.Failure)
        val parseEvent = observer.events.single { it.stage == "adapter_parse" }
        assertNull(parseEvent.request)
        assertNotNull(parseEvent.failure)
        assertEquals("adapter_parse", parseEvent.failure?.stage)
        assertTrue(observer.events.none { it.stage == "policy_pre" })
    }
}
