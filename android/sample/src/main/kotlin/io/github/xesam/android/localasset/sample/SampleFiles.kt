package io.github.xesam.android.localasset.sample

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File

object SampleFiles {
    fun copyAssetDirectory(
        context: Context,
        assetDirectory: String,
        outputDirectory: File,
    ) {
        outputDirectory.mkdirs()
        context.assets.list(assetDirectory)?.forEach { child ->
            val childAssetPath = "$assetDirectory/$child"
            val childOutput = File(outputDirectory, child)
            val nested = context.assets.list(childAssetPath).orEmpty()
            if (nested.isEmpty()) {
                context.assets.open(childAssetPath).use { input ->
                    childOutput.outputStream().use { output -> input.copyTo(output) }
                }
            } else {
                copyAssetDirectory(context, childAssetPath, childOutput)
            }
        }
    }

    fun assetBytes(context: Context, assetPath: String): ByteArray {
        return context.assets.open(assetPath).use { it.readBytes() }
    }

    fun readContentBytes(context: Context, uri: Uri): ByteArray {
        return requireNotNull(context.contentResolver.openInputStream(uri)) {
            "Unable to open input stream for $uri"
        }.use { it.readBytes() }
    }

    fun queryDisplayName(context: Context, uri: Uri): String {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                val columnIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (columnIndex >= 0 && cursor.moveToFirst()) {
                    return cursor.getString(columnIndex)
                }
            }
        return "picked-image"
    }

    fun queryMimeType(context: Context, uri: Uri): String {
        return context.contentResolver.getType(uri) ?: "image/*"
    }

    fun fileNameForMime(
        baseName: String,
        mimeType: String,
    ): String {
        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
        return if (extension.isNullOrBlank() || baseName.endsWith(".$extension")) {
            baseName
        } else {
            "$baseName.$extension"
        }
    }
}
