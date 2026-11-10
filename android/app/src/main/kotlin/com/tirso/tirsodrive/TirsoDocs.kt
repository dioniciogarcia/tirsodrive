package com.tirso.tirsodrive

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.database.MatrixCursor
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import android.webkit.MimeTypeMap
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException

/**
 * Shows TirsoDrive as a storage location in Android's file picker ("Save to…", backups, game saves).
 * Files saved here land in a private inbox and are uploaded to the chosen channel by TirsoDrive (right away if it is
 * open, otherwise the next time it opens — a notification says so). Browsing shows what TirsoDrive last indexed.
 */
class TirsoDocs : DocumentsProvider() {
    companion object {
        /** Set by MainActivity while the app is open: tells Dart a file arrived. */
        @Volatile var onInbox: (() -> Unit)? = null
        const val ROOT = "root"
        private val main = Handler(Looper.getMainLooper())

        fun inboxDir(ctx: Context) = File(ctx.filesDir, "inbox").apply { mkdirs() }
        fun readIndex(ctx: Context): JSONObject? = try {
            JSONObject(File(ctx.filesDir, "td_index.json").readText())
        } catch (_: Exception) { null }
    }

    private val rootCols = arrayOf(Root.COLUMN_ROOT_ID, Root.COLUMN_ICON, Root.COLUMN_TITLE, Root.COLUMN_FLAGS, Root.COLUMN_DOCUMENT_ID, Root.COLUMN_SUMMARY, Root.COLUMN_MIME_TYPES)
    private val docCols = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE, Document.COLUMN_SIZE, Document.COLUMN_LAST_MODIFIED, Document.COLUMN_FLAGS)

    override fun onCreate(): Boolean = true

    override fun queryRoots(projection: Array<out String>?): Cursor {
        val c = MatrixCursor(projection ?: rootCols)
        c.newRow()
            .add(Root.COLUMN_ROOT_ID, "tirsodrive")
            .add(Root.COLUMN_ICON, R.mipmap.ic_launcher)
            .add(Root.COLUMN_TITLE, "TirsoDrive")
            .add(Root.COLUMN_SUMMARY, "Telegram cloud")
            .add(Root.COLUMN_FLAGS, Root.FLAG_SUPPORTS_CREATE or Root.FLAG_SUPPORTS_IS_CHILD)
            .add(Root.COLUMN_DOCUMENT_ID, ROOT)
            .add(Root.COLUMN_MIME_TYPES, "*/*")
        return c
    }

    private fun dirRow(c: MatrixCursor, id: String, name: String, canCreate: Boolean) {
        c.newRow().add(Document.COLUMN_DOCUMENT_ID, id).add(Document.COLUMN_DISPLAY_NAME, name)
            .add(Document.COLUMN_MIME_TYPE, Document.MIME_TYPE_DIR).add(Document.COLUMN_SIZE, 0)
            .add(Document.COLUMN_FLAGS, if (canCreate) Document.FLAG_DIR_SUPPORTS_CREATE else 0)
    }

    private fun mimeOf(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
    }

    private fun chatTitle(chat: Long): String {
        val groups = readIndex(context!!)?.optJSONArray("groups") ?: return "Channel"
        for (i in 0 until groups.length()) { val g = groups.getJSONObject(i); if (g.optLong("chatId") == chat) return g.optString("title") }
        return "Channel"
    }

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
        val c = MatrixCursor(projection ?: docCols)
        when {
            documentId == ROOT -> dirRow(c, ROOT, "TirsoDrive", false)
            documentId.startsWith("c:") -> dirRow(c, documentId, chatTitle(documentId.substring(2).toLong()), true)
            documentId.startsWith("i:") -> {
                val f = inboxFile(documentId)
                c.newRow().add(Document.COLUMN_DOCUMENT_ID, documentId).add(Document.COLUMN_DISPLAY_NAME, f.name)
                    .add(Document.COLUMN_MIME_TYPE, mimeOf(f.name)).add(Document.COLUMN_SIZE, f.length())
                    .add(Document.COLUMN_LAST_MODIFIED, f.lastModified())
                    .add(Document.COLUMN_FLAGS, Document.FLAG_SUPPORTS_WRITE or Document.FLAG_SUPPORTS_DELETE)
            }
            documentId.startsWith("f:") -> {
                val (chat, msg) = documentId.substring(2).split(":").let { it[0].toLong() to it[1].toLong() }
                val files = readIndex(context!!)?.optJSONArray("files")
                if (files != null) for (i in 0 until files.length()) {
                    val f = files.getJSONObject(i)
                    if (f.optLong("c") == chat && f.optLong("i") == msg) { fileRow(c, f); break }
                }
            }
            else -> throw FileNotFoundException(documentId)
        }
        return c
    }

    private fun fileRow(c: MatrixCursor, f: JSONObject) {
        c.newRow().add(Document.COLUMN_DOCUMENT_ID, "f:${f.optLong("c")}:${f.optLong("i")}")
            .add(Document.COLUMN_DISPLAY_NAME, f.optString("n")).add(Document.COLUMN_MIME_TYPE, f.optString("m").ifEmpty { mimeOf(f.optString("n")) })
            .add(Document.COLUMN_SIZE, f.optLong("s")).add(Document.COLUMN_LAST_MODIFIED, f.optLong("d") * 1000).add(Document.COLUMN_FLAGS, 0)
    }

    override fun queryChildDocuments(parentDocumentId: String, projection: Array<out String>?, sortOrder: String?): Cursor {
        val c = MatrixCursor(projection ?: docCols)
        val idx = readIndex(context!!)
        if (parentDocumentId == ROOT) {
            val groups = idx?.optJSONArray("groups")
            if (groups != null) for (i in 0 until groups.length()) {
                val g = groups.getJSONObject(i)
                if (g.optLong("chatId") != 0L) dirRow(c, "c:${g.optLong("chatId")}", g.optString("title"), true)
            }
        } else if (parentDocumentId.startsWith("c:")) {
            val chat = parentDocumentId.substring(2).toLong()
            File(inboxDir(context!!), chat.toString()).listFiles()?.sortedBy { it.name }?.forEach { f ->
                c.newRow().add(Document.COLUMN_DOCUMENT_ID, "i:$chat/${f.name}").add(Document.COLUMN_DISPLAY_NAME, f.name)
                    .add(Document.COLUMN_MIME_TYPE, mimeOf(f.name)).add(Document.COLUMN_SIZE, f.length())
                    .add(Document.COLUMN_LAST_MODIFIED, f.lastModified())
                    .add(Document.COLUMN_FLAGS, Document.FLAG_SUPPORTS_WRITE or Document.FLAG_SUPPORTS_DELETE)
            }
            val files = idx?.optJSONArray("files")
            if (files != null) for (i in 0 until files.length()) {
                val f = files.getJSONObject(i)
                if (f.optLong("c") == chat) fileRow(c, f)
            }
        }
        return c
    }

    private fun inboxFile(id: String): File {
        val rel = id.substring(2)
        val f = File(inboxDir(context!!), rel)
        if (!f.canonicalPath.startsWith(inboxDir(context!!).canonicalPath)) throw FileNotFoundException(id)
        return f
    }

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean =
        documentId == parentDocumentId || (parentDocumentId == ROOT) ||
            (parentDocumentId.startsWith("c:") && (documentId.startsWith("i:${parentDocumentId.substring(2)}/") || documentId.startsWith("f:${parentDocumentId.substring(2)}:")))

    override fun createDocument(parentDocumentId: String, mimeType: String, displayName: String): String {
        if (!parentDocumentId.startsWith("c:") || mimeType == Document.MIME_TYPE_DIR) throw FileNotFoundException("Save inside a channel folder")
        val chat = parentDocumentId.substring(2)
        val dir = File(inboxDir(context!!), chat).apply { mkdirs() }
        var name = displayName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        var f = File(dir, name)
        var n = 1
        while (f.exists()) { val dot = name.lastIndexOf('.'); f = File(dir, if (dot > 0) "${name.substring(0, dot)} ($n)${name.substring(dot)}" else "$name ($n)"); n++ }
        f.createNewFile()
        return "i:$chat/${f.name}"
    }

    override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor {
        if (!documentId.startsWith("i:")) throw FileNotFoundException("Open TirsoDrive to download this file first")
        val f = inboxFile(documentId)
        val pfdMode = ParcelFileDescriptor.parseMode(mode)
        if (!mode.contains('w')) return ParcelFileDescriptor.open(f, pfdMode)
        return ParcelFileDescriptor.open(f, pfdMode, main) { _ -> fileWritten(f) }
    }

    private fun fileWritten(f: File) {
        val ctx = context ?: return
        val cb = onInbox
        if (cb != null) { main.post { cb() }; return }
        // TirsoDrive isn't open: leave a notification, the upload happens when it opens
        try {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= 26) nm.createNotificationChannel(NotificationChannel("inbox", "Files waiting", NotificationManager.IMPORTANCE_DEFAULT))
            val pi = PendingIntent.getActivity(ctx, 0, Intent(ctx, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val b = if (Build.VERSION.SDK_INT >= 26) android.app.Notification.Builder(ctx, "inbox") else android.app.Notification.Builder(ctx)
            nm.notify(7311, b.setSmallIcon(android.R.drawable.stat_sys_upload).setContentTitle("TirsoDrive")
                .setContentText("${f.name} is waiting. Open TirsoDrive to upload it.").setContentIntent(pi).setAutoCancel(true).build())
        } catch (_: Exception) { }
    }

    override fun deleteDocument(documentId: String) {
        if (documentId.startsWith("i:")) inboxFile(documentId).delete() else throw FileNotFoundException("Delete files from inside TirsoDrive")
    }
}
