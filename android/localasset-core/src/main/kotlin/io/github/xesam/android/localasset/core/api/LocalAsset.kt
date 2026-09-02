package io.github.xesam.android.localasset.core.api

import io.github.xesam.android.localasset.core.engine.DefaultLocalAssetEngine
import io.github.xesam.android.localasset.core.engine.DefaultLocalAssetSchemeAdapter
import io.github.xesam.android.localasset.core.internal.ResolverChain
import io.github.xesam.android.localasset.core.loader.BytesResourceLoader
import io.github.xesam.android.localasset.core.loader.CompositeResourceLoader
import io.github.xesam.android.localasset.core.loader.FileResourceLoader
import io.github.xesam.android.localasset.core.loader.StreamResourceLoader
import io.github.xesam.android.localasset.core.model.ResourceHandle
import io.github.xesam.android.localasset.core.model.ResourceHandleRecord
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.policy.DefaultPolicy
import io.github.xesam.android.localasset.core.registry.InMemoryHandleRegistry
import io.github.xesam.android.localasset.core.registry.InMemoryResourceRegistry
import io.github.xesam.android.localasset.core.resolver.HandleRegistryResolver
import io.github.xesam.android.localasset.core.resolver.RegistryResolver

class LocalAsset private constructor(
    val engine: LocalAssetEngine,
    private val registry: ResourceRegistry,
    private val handleRegistry: HandleRegistry,
) {
    fun register(descriptor: ResourceDescriptor) {
        registry.register(descriptor)
    }

    fun unregister(id: String) {
        registry.remove(id)
    }

    fun registerHandle(handle: ResourceHandle): String {
        return handleRegistry.register(handle)
    }

    fun resolveHandle(resourceUri: String): ResourceHandleRecord {
        return handleRegistry.resolve(resourceUri)
    }

    fun removeHandle(resourceUri: String) {
        handleRegistry.remove(resourceUri)
    }

    fun cleanup() {
        registry.cleanup()
    }

    fun cleanupHandles() {
        handleRegistry.cleanup()
    }

    /**
     * Builds a [LocalAsset] instance. Per `design.md §3.1`, each instance is independently
     * constructed and holds no global/static state — build a fresh [Builder] per engine instance.
     *
     * Final resolver chain order (`design.md §3.4`, not reorderable via this Builder):
     * `HandleRegistryResolver` (always first) → resolvers added via [addResolver], in call order →
     * `RegistryResolver` (always appended as the fallback backing [LocalAsset.register]).
     */
    class Builder {
        private val adapters = mutableListOf<SchemeAdapter>()
        private val resolvers = mutableListOf<ResourceResolver>()
        private val allowedFileRoots = mutableListOf<java.io.File>()
        private val allowedNamespaces = mutableSetOf<String>()
        private val allowedSchemes = mutableSetOf<String>()
        private var registry: ResourceRegistry? = null
        private var handleRegistry: HandleRegistry? = null
        private var policy: Policy? = null
        private var loader: ResourceLoader? = null
        private var observer: EngineObserver? = null

        fun addAdapter(adapter: SchemeAdapter): Builder = apply {
            adapters += adapter
        }

        /** Appends [resolver] to the end of the user-resolver segment of the chain. */
        fun addResolver(resolver: ResourceResolver): Builder = apply {
            resolvers += resolver
        }

        /**
         * Adds a directory that the default [DefaultPolicy] will accept `FilePath` resources from.
         *
         * The default policy is fail-closed: with no allowed roots, every `ResourceSource.FilePath`
         * descriptor is rejected at postCheck ("file source is outside allowed roots"). Add every
         * root you want `FilePath` resources to live under here instead of hand-building a
         * [DefaultPolicy]. Ignored when a custom [policy] is supplied — in that case configure
         * allowed roots on your own [Policy].
         */
        fun addAllowedFileRoot(root: java.io.File): Builder = apply {
            allowedFileRoots += root
        }

        /** Bulk variant of [addAllowedFileRoot]. */
        fun addAllowedFileRoots(roots: Collection<java.io.File>): Builder = apply {
            allowedFileRoots += roots
        }

        /**
         * Adds a namespace the default [DefaultPolicy] will accept at preCheck (design.md §5.2
         * "namespace 白名单"). With no namespaces added, every non-blank namespace is accepted
         * (fail-open default, preserves existing behavior). Ignored when a custom [policy] is
         * supplied.
         */
        fun addAllowedNamespace(namespace: String): Builder = apply {
            allowedNamespaces += namespace
        }

        /** Bulk variant of [addAllowedNamespace]. */
        fun addAllowedNamespaces(namespaces: Collection<String>): Builder = apply {
            allowedNamespaces += namespaces
        }

        /**
         * Adds a scheme the default [DefaultPolicy] will accept at preCheck (design.md §5.2
         * "scheme 合法性"). With no schemes added, every non-blank scheme is accepted. Ignored
         * when a custom [policy] is supplied.
         */
        fun addAllowedScheme(scheme: String): Builder = apply {
            allowedSchemes += scheme
        }

        /** Bulk variant of [addAllowedScheme]. */
        fun addAllowedSchemes(schemes: Collection<String>): Builder = apply {
            allowedSchemes += schemes
        }

        fun registry(registry: ResourceRegistry): Builder = apply {
            this.registry = registry
        }

        fun handleRegistry(handleRegistry: HandleRegistry): Builder = apply {
            this.handleRegistry = handleRegistry
        }

        fun policy(policy: Policy): Builder = apply {
            this.policy = policy
        }

        fun loader(loader: ResourceLoader): Builder = apply {
            this.loader = loader
        }

        /**
         * Attaches an [EngineObserver] to the default engine so each stage of the pipeline
         * (adapter parse, policy pre/post, every resolver's decision, load, terminal outcome)
         * fires an [EngineStageEvent] — design.md §8. No-op when a custom engine is used.
         */
        fun observer(observer: EngineObserver): Builder = apply {
            this.observer = observer
        }

        fun build(): LocalAsset {
            val resolvedRegistry = registry ?: InMemoryResourceRegistry()
            val resolvedHandleRegistry = handleRegistry ?: InMemoryHandleRegistry()
            val resolvedAdapters = adapters.ifEmpty { listOf(DefaultLocalAssetSchemeAdapter()) }
            val resolvedResolvers = listOf(HandleRegistryResolver(resolvedHandleRegistry)) +
                resolvers +
                listOf(RegistryResolver(resolvedRegistry))
            val resolvedPolicy = policy ?: DefaultPolicy(
                allowedFileRoots = allowedFileRoots.toSet(),
                allowedNamespaces = allowedNamespaces.toSet(),
                allowedSchemes = allowedSchemes.toSet(),
            )
            val resolvedLoader = loader ?: CompositeResourceLoader(
                listOf(BytesResourceLoader(), FileResourceLoader(), StreamResourceLoader()),
            )
            val engine = DefaultLocalAssetEngine(
                adapters = resolvedAdapters,
                resolverChain = ResolverChain(resolvedResolvers),
                policy = resolvedPolicy,
                loader = resolvedLoader,
                observer = observer,
            )
            return LocalAsset(
                engine = engine,
                registry = resolvedRegistry,
                handleRegistry = resolvedHandleRegistry,
            )
        }
    }
}
