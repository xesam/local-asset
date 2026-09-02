package io.github.xesam.android.localasset.core.engine

import io.github.xesam.android.localasset.core.api.SchemeAdapter
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.model.AssetRequest
import java.net.URI
import java.net.URLDecoder

class DefaultLocalAssetSchemeAdapter : SchemeAdapter {
    override fun canHandle(url: String): Boolean = runCatching {
        URI(url).scheme == "local-asset"
    }.getOrDefault(false)

    override fun parse(url: String): AssetRequest {
        val uri = runCatching { URI(url) }.getOrElse {
            throw ResourceException(ResourceErrorCategory.PARSE_ERROR, "invalid url")
        }
        if (uri.scheme != "local-asset") {
            throw ResourceException(ResourceErrorCategory.PARSE_ERROR, "unsupported scheme")
        }
        val namespace = uri.host?.takeIf { it.isNotBlank() }
            ?: throw ResourceException(ResourceErrorCategory.PARSE_ERROR, "missing namespace")
        val rawPath = uri.path?.takeIf { it.isNotBlank() }
            ?: throw ResourceException(ResourceErrorCategory.PARSE_ERROR, "missing path")
        val path = if (rawPath.startsWith("/")) rawPath else "/$rawPath"
        val identifier = path.substringAfterLast('/').takeIf { it.isNotBlank() }
        return AssetRequest(
            scheme = uri.scheme,
            namespace = namespace,
            identifier = identifier,
            path = path,
            query = parseQuery(uri.rawQuery),
            fragment = uri.fragment,
        )
    }

    private fun parseQuery(rawQuery: String?): Map<String, String> {
        if (rawQuery.isNullOrBlank()) return emptyMap()
        return rawQuery.split("&")
            .filter { it.isNotBlank() }
            .associate { part ->
                val pieces = part.split("=", limit = 2)
                decode(pieces[0]) to decode(pieces.getOrElse(1) { "" })
            }
    }

    private fun decode(value: String): String = URLDecoder.decode(value, "UTF-8")
}
