package io.github.xesam.android.localasset.core.policy

import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceScope
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType
import java.io.File
import kotlin.io.path.createTempDirectory
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class DefaultPolicyTest {
    @Test
    fun rejects_blank_namespace_in_precheck() {
        val policy = DefaultPolicy()

        val error = assertFailsWith<ResourceException> {
            policy.preCheck(
                AssetRequest(
                    scheme = "local-asset",
                    namespace = "",
                    identifier = "logo",
                    path = null,
                    query = emptyMap(),
                    fragment = null,
                ),
                ResolveContext(null, null, null, null),
            )
        }

        assertEquals(ResourceErrorCategory.SECURITY_ERROR, error.category)
    }

    @Test
    fun rejects_unsupported_source_type_in_postcheck() {
        val policy = DefaultPolicy(allowedSourceTypes = setOf(ResourceSource.FilePath::class))

        val error = assertFailsWith<ResourceException> {
            policy.postCheck(
                AssetRequest(
                    scheme = "local-asset",
                    namespace = "demo",
                    identifier = "logo",
                    path = null,
                    query = emptyMap(),
                    fragment = null,
                ),
                ResourceDescriptor(
                    id = "logo",
                    namespace = "demo",
                    type = ResourceType.DYNAMIC,
                    source = ResourceSource.Bytes(byteArrayOf(1)),
                    mimeType = "text/plain",
                    createdAtMillis = 0L,
                    ttlMillis = null,
                    scope = null,
                ),
                ResolveContext(null, null, null, null),
            )
        }

        assertEquals(ResourceErrorCategory.SECURITY_ERROR, error.category)
    }

    @Test
    fun rejects_filepath_outside_allowed_roots() {
        val root = createTempDirectory(prefix = "policy-root").toFile()
        val outside = createTempDirectory(prefix = "policy-outside").toFile()
        val policy = DefaultPolicy(allowedFileRoots = setOf(root))
        val outsideFile = File(outside, "outside.txt").apply { writeText("x") }

        val error = assertFailsWith<ResourceException> {
            policy.postCheck(
                request = AssetRequest(
                    scheme = "local-asset",
                    namespace = "demo",
                    identifier = "outside",
                    path = "/outside.txt",
                    query = emptyMap(),
                    fragment = null,
                ),
                descriptor = ResourceDescriptor(
                    id = "outside",
                    namespace = "demo",
                    type = ResourceType.DYNAMIC,
                    source = ResourceSource.FilePath(outsideFile.absolutePath),
                    mimeType = "text/plain",
                    createdAtMillis = 0L,
                    ttlMillis = null,
                    scope = null,
                ),
                context = ResolveContext(null, null, null, null),
            )
        }

        assertEquals(ResourceErrorCategory.SECURITY_ERROR, error.category)
    }

    @Test
    fun rejects_engine_scope_mismatch() {
        val policy = DefaultPolicy()

        val error = assertFailsWith<ResourceException> {
            policy.postCheck(
                request = AssetRequest(
                    scheme = "local-asset",
                    namespace = "demo",
                    identifier = "logo",
                    path = "/logo",
                    query = emptyMap(),
                    fragment = null,
                ),
                descriptor = ResourceDescriptor(
                    id = "logo",
                    namespace = "demo",
                    type = ResourceType.DYNAMIC,
                    source = ResourceSource.Bytes(byteArrayOf(1)),
                    mimeType = "text/plain",
                    createdAtMillis = 0L,
                    ttlMillis = null,
                    scope = ResourceScope.ENGINE,
                ),
                context = ResolveContext(
                    engineScope = "another-engine",
                    callerScope = null,
                    pageScope = null,
                    sessionScope = null,
                ),
            )
        }

        assertEquals(ResourceErrorCategory.SECURITY_ERROR, error.category)
    }

    @Test
    fun rejects_expired_resource_in_postcheck() {
        val now = 10_000L
        val policy = DefaultPolicy(nowMillis = { now })

        val error = assertFailsWith<ResourceException> {
            policy.postCheck(
                AssetRequest(
                    scheme = "local-asset",
                    namespace = "demo",
                    identifier = "expired",
                    path = "/expired",
                    query = emptyMap(),
                    fragment = null,
                ),
                ResourceDescriptor(
                    id = "expired",
                    namespace = "demo",
                    type = ResourceType.DYNAMIC,
                    source = ResourceSource.Bytes(byteArrayOf(1)),
                    mimeType = "text/plain",
                    createdAtMillis = 0L,
                    ttlMillis = 5_000L,
                    scope = null,
                ),
                ResolveContext(null, null, null, null),
            )
        }

        assertEquals(ResourceErrorCategory.RESOLUTION_ERROR, error.category)
    }

    @Test
    fun allows_page_scoped_resource_when_page_scope_matches() {
        val policy = DefaultPolicy()
        policy.postCheck(
            AssetRequest(
                scheme = "local-asset",
                namespace = "demo-page",
                identifier = "page-res",
                path = "/page-res",
                query = emptyMap(),
                fragment = null,
            ),
            ResourceDescriptor(
                id = "page-res",
                namespace = "demo-page",
                type = ResourceType.DYNAMIC,
                source = ResourceSource.Bytes(byteArrayOf(1)),
                mimeType = "text/plain",
                createdAtMillis = 0L,
                ttlMillis = null,
                scope = ResourceScope.PAGE,
            ),
            ResolveContext(
                engineScope = null,
                callerScope = null,
                pageScope = "demo-page",
                sessionScope = null,
            ),
        )
    }

    @Test
    fun allows_session_scoped_resource_when_session_scope_matches() {
        val policy = DefaultPolicy()
        policy.postCheck(
            AssetRequest(
                scheme = "local-asset",
                namespace = "demo-session",
                identifier = "session-res",
                path = "/session-res",
                query = emptyMap(),
                fragment = null,
            ),
            ResourceDescriptor(
                id = "session-res",
                namespace = "demo-session",
                type = ResourceType.DYNAMIC,
                source = ResourceSource.Bytes(byteArrayOf(1)),
                mimeType = "text/plain",
                createdAtMillis = 0L,
                ttlMillis = null,
                scope = ResourceScope.SESSION,
            ),
            ResolveContext(
                engineScope = null,
                callerScope = null,
                pageScope = null,
                sessionScope = "demo-session",
            ),
        )
    }

    @Test
    fun rejects_page_scope_mismatch() {
        val policy = DefaultPolicy()

        val error = assertFailsWith<ResourceException> {
            policy.postCheck(
                AssetRequest(
                    scheme = "local-asset",
                    namespace = "demo",
                    identifier = "page-res",
                    path = "/page-res",
                    query = emptyMap(),
                    fragment = null,
                ),
                ResourceDescriptor(
                    id = "page-res",
                    namespace = "demo",
                    type = ResourceType.DYNAMIC,
                    source = ResourceSource.Bytes(byteArrayOf(1)),
                    mimeType = "text/plain",
                    createdAtMillis = 0L,
                    ttlMillis = null,
                    scope = ResourceScope.PAGE,
                ),
                ResolveContext(
                    engineScope = null,
                    callerScope = null,
                    pageScope = "another-page",
                    sessionScope = null,
                ),
            )
        }

        assertEquals(ResourceErrorCategory.SECURITY_ERROR, error.category)
    }

    @Test
    fun rejects_session_scope_mismatch() {
        val policy = DefaultPolicy()

        val error = assertFailsWith<ResourceException> {
            policy.postCheck(
                AssetRequest(
                    scheme = "local-asset",
                    namespace = "demo",
                    identifier = "session-res",
                    path = "/session-res",
                    query = emptyMap(),
                    fragment = null,
                ),
                ResourceDescriptor(
                    id = "session-res",
                    namespace = "demo",
                    type = ResourceType.DYNAMIC,
                    source = ResourceSource.Bytes(byteArrayOf(1)),
                    mimeType = "text/plain",
                    createdAtMillis = 0L,
                    ttlMillis = null,
                    scope = ResourceScope.SESSION,
                ),
                ResolveContext(
                    engineScope = null,
                    callerScope = null,
                    pageScope = null,
                    sessionScope = "another-session",
                ),
            )
        }

        assertEquals(ResourceErrorCategory.SECURITY_ERROR, error.category)
    }

    @Test
    fun rejects_blank_scheme_in_precheck() {
        val policy = DefaultPolicy()
        val error = assertFailsWith<ResourceException> {
            policy.preCheck(
                AssetRequest(
                    scheme = "",
                    namespace = "demo",
                    identifier = "logo",
                    path = "/logo",
                    query = emptyMap(),
                    fragment = null,
                ),
                ResolveContext(null, null, null, null),
            )
        }
        assertEquals(ResourceErrorCategory.SECURITY_ERROR, error.category)
        assertEquals("policy_pre", error.stage)
    }

    @Test
    fun rejects_scheme_not_in_allow_list() {
        val policy = DefaultPolicy(allowedSchemes = setOf("local-asset"))
        val error = assertFailsWith<ResourceException> {
            policy.preCheck(
                AssetRequest(
                    scheme = "https",
                    namespace = "demo",
                    identifier = "logo",
                    path = "/logo",
                    query = emptyMap(),
                    fragment = null,
                ),
                ResolveContext(null, null, null, null),
            )
        }
        assertEquals(ResourceErrorCategory.SECURITY_ERROR, error.category)
        assertEquals("policy_pre", error.stage)
    }

    @Test
    fun allows_any_non_blank_scheme_when_allow_list_empty() {
        val policy = DefaultPolicy()
        policy.preCheck(
            AssetRequest(
                scheme = "custom-scheme",
                namespace = "demo",
                identifier = "logo",
                path = "/logo",
                query = emptyMap(),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )
    }

    @Test
    fun rejects_namespace_not_in_allow_list() {
        val policy = DefaultPolicy(allowedNamespaces = setOf("allowed"))
        val error = assertFailsWith<ResourceException> {
            policy.preCheck(
                AssetRequest(
                    scheme = "local-asset",
                    namespace = "forbidden",
                    identifier = "logo",
                    path = "/logo",
                    query = emptyMap(),
                    fragment = null,
                ),
                ResolveContext(null, null, null, null),
            )
        }
        assertEquals(ResourceErrorCategory.SECURITY_ERROR, error.category)
        assertEquals("policy_pre", error.stage)
    }

    @Test
    fun allows_any_non_blank_namespace_when_allow_list_empty() {
        val policy = DefaultPolicy()
        policy.preCheck(
            AssetRequest(
                scheme = "local-asset",
                namespace = "any-ad-hoc-namespace",
                identifier = "logo",
                path = "/logo",
                query = emptyMap(),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )
    }

    @Test
    fun allowed_namespace_list_does_not_break_handle_uris() {
        // Footgun regression: declaring addAllowedNamespace used to reject every handle URI because
        // handle URIs live under the fixed namespace "handles.localasset.local", which is not in
        // the user's list. The Handle path is authorized by its capability token, not by namespace,
        // so DefaultPolicy exempts the handle host from the namespace allow-list.
        val policy = DefaultPolicy(allowedNamespaces = setOf("foo"))
        policy.preCheck(
            AssetRequest(
                scheme = "local-asset",
                namespace = "handles.localasset.local",
                identifier = "abc",
                path = "/handles/abc/file.png",
                query = emptyMap(),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )
    }

    @Test
    fun custom_handle_host_is_exempt_when_passed_to_policy() {
        val policy = DefaultPolicy(allowedNamespaces = setOf("foo"), handleHost = "my-handles.local")
        policy.preCheck(
            AssetRequest(
                scheme = "local-asset",
                namespace = "my-handles.local",
                identifier = "abc",
                path = "/handles/abc/file.png",
                query = emptyMap(),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )
    }

    @Test
    fun rejects_path_traversal_segment_in_precheck() {
        val policy = DefaultPolicy()
        val error = assertFailsWith<ResourceException> {
            policy.preCheck(
                AssetRequest(
                    scheme = "local-asset",
                    namespace = "demo",
                    identifier = "..",
                    path = "/pkg/../etc/passwd",
                    query = emptyMap(),
                    fragment = null,
                ),
                ResolveContext(null, null, null, null),
            )
        }
        assertEquals(ResourceErrorCategory.SECURITY_ERROR, error.category)
        assertEquals("policy_pre", error.stage)
    }

    @Test
    fun rejects_traversal_only_when_full_segment_matches() {
        // A path that merely contains ".." as part of a longer segment (e.g. "my..file") is NOT
        // traversal and must still pass preCheck; only a literal ".." segment is rejected.
        val policy = DefaultPolicy()
        policy.preCheck(
            AssetRequest(
                scheme = "local-asset",
                namespace = "demo",
                identifier = "my..file.js",
                path = "/assets/my..file.js",
                query = emptyMap(),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )
    }

    @Test
    fun allows_stream_source_by_default() {
        // Stream is opaque to postCheck (no path to contain), same as Bytes — both are default-allowed
        // and rely on resolver-side containment. No allowedFileRoots configured; must still pass.
        val policy = DefaultPolicy()
        policy.postCheck(
            AssetRequest(
                scheme = "local-asset",
                namespace = "demo",
                identifier = "logo",
                path = "/logo",
                query = emptyMap(),
                fragment = null,
            ),
            ResourceDescriptor(
                id = "logo",
                namespace = "demo",
                type = ResourceType.STATIC,
                source = ResourceSource.Stream { java.io.ByteArrayInputStream(ByteArray(0)) },
                mimeType = "text/plain",
                createdAtMillis = 0L,
                ttlMillis = null,
                scope = null,
            ),
            ResolveContext(null, null, null, null),
        )
    }

    @Test
    fun rejects_stream_source_when_not_in_allowed_types() {
        val policy = DefaultPolicy(
            allowedSourceTypes = setOf(ResourceSource.Bytes::class, ResourceSource.FilePath::class),
        )

        val error = assertFailsWith<ResourceException> {
            policy.postCheck(
                AssetRequest(
                    scheme = "local-asset",
                    namespace = "demo",
                    identifier = "logo",
                    path = "/logo",
                    query = emptyMap(),
                    fragment = null,
                ),
                ResourceDescriptor(
                    id = "logo",
                    namespace = "demo",
                    type = ResourceType.STATIC,
                    source = ResourceSource.Stream { java.io.ByteArrayInputStream(ByteArray(0)) },
                    mimeType = "text/plain",
                    createdAtMillis = 0L,
                    ttlMillis = null,
                    scope = null,
                ),
                ResolveContext(null, null, null, null),
            )
        }

        assertEquals(ResourceErrorCategory.SECURITY_ERROR, error.category)
    }
}
