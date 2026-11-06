package com.tirso.tirsodrive

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Lets other apps (WhatsApp, Instagram, Drive…) read a downloaded file directly, under its TirsoDrive name,
 * without making a second copy on the phone. Links only work while TirsoDrive is running.
 */
class ShareProvider : ContentProvider() {
    companion object {
        private val files = ConcurrentHashMap<String, Pair<String, String>>() // token -> (path, display name)

        fun uriFor(ctx: Context, path: String, name: String): Uri {
            val token = UUID.randomUUID().toString()
            files[token] = path to name
            return Uri.parse("content://${ctx.packageName}.share/$token/${Uri.encode(name)}")
        }
    }

    private fun entry(uri: Uri): Pair<String, String>? = uri.pathSegments.firstOrNull()?.let { files[it] }

    override fun onCreate(): Boolean = true

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? {
        val (path, name) = entry(uri) ?: return null
        val cols = projection?.filter { it == OpenableColumns.DISPLAY_NAME || it == OpenableColumns.SIZE }?.toTypedArray()
            ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val c = MatrixCursor(cols)
        c.addRow(cols.map<String, Any> { if (it == OpenableColumns.DISPLAY_NAME) name else File(path).length() }.toTypedArray())
        return c
    }

    override fun getType(uri: Uri): String {
        val name = entry(uri)?.second ?: return "application/octet-stream"
        val ext = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        val (path, _) = entry(uri) ?: return null
        return ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
