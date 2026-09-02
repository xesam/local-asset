package io.github.xesam.android.localasset.core.policy

import io.github.xesam.android.localasset.core.api.HandleRegistry
import io.github.xesam.android.localasset.core.api.Policy
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceScope
import java.io.File
import kotlin.reflect.KClass

class DefaultPolicy(
    private val allowedSourceTypes: Set<KClass<out ResourceSource>> = setOf(
        ResourceSource.Bytes::class,
        ResourceSource.FilePath::class,
        ResourceSource.Stream::class,
    ),
    private val allowedFileRoots: Set<File> = emptySet(),
    /**
     * Optional scheme allow-list (request-level). Empty (default) = unrestricted; every non-blank
     * scheme passes. When non-empty, a request whose scheme is not in the set is rejected at
     * preCheck. Matches design.md §5.2 "scheme 合法性".
     */
    private val allowedSchemes: Set<String> = emptySet(),
    /**
     * Optional namespace allow-list (request-level). Empty (default) = unrestricted; every
     * non-blank namespace passes (preserves the fail-open default so existing callers that rely on
     * ad-hoc namespaces keep resolving). When non-empty, a request whose namespace is not in the
     * set is rejected at preCheck — **except** the handle namespace ([handleHost]), which is always
     * exempt because the Handle path is authorized by its capability token, not by namespace
     * (design.md §5.4). Without this exemption, declaring `addAllowedNamespace("foo")` would
     * silently reject every handle URI minted under `handles.localasset.local`. Matches design.md
     * §5.2 "namespace 白名单".
     */
    private val allowedNamespaces: Set<String> = emptySet(),
    /**
     * Namespace under which handle URIs are minted; always exempt from [allowedNamespaces].
     * Defaults to [HandleRegistry.DEFAULT_HANDLE_HOST]. Pass a custom value only when using a
     * custom [HandleRegistry][io.github.xesam.android.localasset.core.api.HandleRegistry] that
     * mints under a different host.
     */
    private val handleHost: String = HandleRegistry.DEFAULT_HANDLE_HOST,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) : Policy {
    private val allowedFileRootPaths: Set<String> by lazy { allowedFileRoots.map { it.canonicalFile.path }.toSet() }

    override fun preCheck(request: AssetRequest, context: ResolveContext) {
        if (request.scheme.isBlank()) {
            throw ResourceException(
                category = ResourceErrorCategory.SECURITY_ERROR,
                message = "scheme must not be blank",
                stage = "policy_pre",
            )
        }
        if (allowedSchemes.isNotEmpty() && request.scheme !in allowedSchemes) {
            throw ResourceException(
                category = ResourceErrorCategory.SECURITY_ERROR,
                message = "scheme is not allowed: ${request.scheme}",
                stage = "policy_pre",
            )
        }
        if (request.namespace.isBlank()) {
            throw ResourceException(
                category = ResourceErrorCategory.SECURITY_ERROR,
                message = "namespace must not be blank",
                stage = "policy_pre",
            )
        }
        if (allowedNamespaces.isNotEmpty() && request.namespace != handleHost && request.namespace !in allowedNamespaces) {
            throw ResourceException(
                category = ResourceErrorCategory.SECURITY_ERROR,
                message = "namespace is not allowed: ${request.namespace}",
                stage = "policy_pre",
            )
        }
        // Request-level path-traversal gate (defense in depth before any resolver sees the path).
        // A `..` segment in an `local-asset://` path is never legitimate and lets directory-scoped
        // resolvers escape their root; reject it here as a SECURITY_ERROR rather than relying on
        // each resolver's own containment check. Matches design.md §5.2 "identifier/path 格式".
        if (containsTraversalSegment(request.path) || containsTraversalSegment(request.identifier)) {
            throw ResourceException(
                category = ResourceErrorCategory.SECURITY_ERROR,
                message = "path traversal is not allowed",
                stage = "policy_pre",
            )
        }
    }

    private fun containsTraversalSegment(value: String?): Boolean {
        if (value.isNullOrBlank()) return false
        return value.split('/').any { it == ".." }
    }

    override fun postCheck(
        request: AssetRequest,
        descriptor: ResourceDescriptor,
        context: ResolveContext,
    ) {
        descriptor.ttlMillis?.let { ttlMillis ->
            if (descriptor.createdAtMillis + ttlMillis <= nowMillis()) {
                throw ResourceException(
                    category = ResourceErrorCategory.RESOLUTION_ERROR,
                    message = "resource expired",
                    stage = "policy_post",
                )
            }
        }
        val expectedScopeId = when (descriptor.scope) {
            ResourceScope.ENGINE -> context.engineScope
            ResourceScope.PAGE -> context.pageScope
            ResourceScope.SESSION -> context.sessionScope
            null -> null
        }
        if (descriptor.scope != null && descriptor.namespace != expectedScopeId) {
            throw ResourceException(
                category = ResourceErrorCategory.SECURITY_ERROR,
                message = "${descriptor.scope.name.lowercase()} scope mismatch",
                stage = "policy_post",
            )
        }
        if (descriptor.source::class !in allowedSourceTypes) {
            throw ResourceException(
                category = ResourceErrorCategory.SECURITY_ERROR,
                message = "source type is not allowed: ${descriptor.source::class.simpleName}",
                stage = "policy_post",
            )
        }
        val source = descriptor.source as? ResourceSource.FilePath
        if (source != null && !isAllowedFilePath(source.value)) {
            throw ResourceException(
                category = ResourceErrorCategory.SECURITY_ERROR,
                message = "file source is outside allowed roots",
                stage = "policy_post",
            )
        }
    }

    private fun isAllowedFilePath(path: String): Boolean {
        if (allowedFileRootPaths.isEmpty()) return false
        val filePath = runCatching { File(path).canonicalFile.path }.getOrNull() ?: return false
        return allowedFileRootPaths.any { root ->
            filePath == root || filePath.startsWith("$root${File.separator}")
        }
    }
}
