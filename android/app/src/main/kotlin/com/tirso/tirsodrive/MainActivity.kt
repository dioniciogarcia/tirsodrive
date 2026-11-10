package com.tirso.tirsodrive

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

/**
 * Small native helper for TirsoDrive:
 *  - pickFiles: system file picker, returns name/size/date for each file (no copying yet)
 *  - copyToCache: copies ONE picked file to a private temp file right before it uploads
 *  - saveToDownloads: puts a downloaded file into the phone's Download/TirsoDrive folder
 *  - openFile: opens a downloaded file in another app (video player, gallery, emulator...)
 *  - keepAwake: keeps the screen on while transfers run
 */
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "tirsodrive/native"
    private val pickRequest = 4711
    private val treeRequest = 4713
    private var pendingTree: MethodChannel.Result? = null
    private var pendingPick: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onDestroy() {
        TirsoDocs.onInbox = null
        WearBridge.onShare = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        TransferService.onTogglePause = { main.post { channel.invokeMethod("togglePause", null) } }
        TirsoDocs.onInbox = { main.post { channel.invokeMethod("inboxChanged", null) } }
        WearBridge.onShare = { main.post { channel.invokeMethod("wearShare", null) } }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "serviceUpdate" -> {
                    try {
                        val i = Intent(this, TransferService::class.java).setAction(TransferService.ACTION_UPDATE)
                        i.putExtra("title", call.argument<String>("title"))
                        i.putExtra("text", call.argument<String>("text"))
                        i.putExtra("progress", call.argument<Int>("progress") ?: -1)
                        i.putExtra("paused", call.argument<Boolean>("paused") ?: false)
                        i.putExtra("button", call.argument<String>("button"))
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i) else startService(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("service", e.message, null)
                    }
                }
                "serviceStop" -> {
                    if (TransferService.running) {
                        try { startService(Intent(this, TransferService::class.java).setAction(TransferService.ACTION_STOP)) } catch (_: Exception) { }
                    }
                    result.success(true)
                }
                "pickTree" -> {
                    if (pendingTree != null) { result.error("busy", "Picker already open", null) } else {
                        pendingTree = result
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION), treeRequest)
                        } catch (e: Exception) { pendingTree = null; result.error("no_picker", e.message, null) }
                    }
                }
                "listTree" -> background(result) { listTree(call.argument<String>("uri")!!) }
                "writeToTree" -> background(result) {
                    writeToTree(call.argument<String>("tree")!!, call.argument<String>("rel")!!, call.argument<String>("src")!!)
                }
                "shareFiles" -> background(result) {
                    shareFiles(call.argument<List<String>>("paths")!!, call.argument<List<String>>("names")!!, call.argument<List<String>>("mimes")!!)
                    true
                }
                "deviceState" -> {
                    var wifi: Boolean? = null
                    try {
                        val cm = getSystemService(android.content.Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
                        val caps = cm.getNetworkCapabilities(cm.activeNetwork)
                        wifi = caps != null && (caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) ||
                            caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_ETHERNET) ||
                            (caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_VPN) &&
                                caps.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_NOT_METERED)))
                    } catch (_: Exception) { }
                    var charging: Boolean? = null
                    try {
                        val bm = getSystemService(android.content.Context.BATTERY_SERVICE) as android.os.BatteryManager
                        charging = bm.isCharging
                    } catch (_: Exception) { }
                    result.success(mapOf("wifi" to wifi, "charging" to charging))
                }
                "videoThumb" -> {
                    val src = call.argument<String>("src")!!
                    val out = call.argument<String>("out")!!
                    Thread {
                        var res: Map<String, Int>? = null
                        try {
                            val mmr = android.media.MediaMetadataRetriever()
                            mmr.setDataSource(src)
                            val dur = (mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION) ?: "0").toLongOrNull() ?: 0L
                            var bmp = mmr.getFrameAtTime(minOf(dur * 1000 / 10, 3_000_000L), android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                                ?: mmr.getFrameAtTime(0)
                            mmr.release()
                            if (bmp != null) {
                                val scale = 320f / maxOf(bmp.width, bmp.height)
                                if (scale < 1f) bmp = android.graphics.Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt().coerceAtLeast(1), (bmp.height * scale).toInt().coerceAtLeast(1), true)
                                java.io.FileOutputStream(out).use { bmp.compress(android.graphics.Bitmap.CompressFormat.JPEG, 78, it) }
                                res = mapOf("w" to bmp.width, "h" to bmp.height)
                            }
                        } catch (_: Exception) { }
                        runOnUiThread { result.success(res) }
                    }.start()
                }
                "isTv" -> {
                    val ui = getSystemService(android.content.Context.UI_MODE_SERVICE) as android.app.UiModeManager
                    result.success(ui.currentModeType == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION ||
                        packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK))
                }
                "askNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4712)
                    }
                    result.success(true)
                }
                "pickFiles" -> pickFiles(result)
                "copyToCache" -> background(result) {
                    copyToCache(call.argument<String>("uri")!!, call.argument<String>("name")!!)
                }
                "saveToDownloads" -> background(result) {
                    saveToDownloads(call.argument<String>("path")!!, call.argument<String>("name")!!, call.argument<String>("mime") ?: "application/octet-stream")
                }
                "openFile" -> {
                    try {
                        openFile(call.argument<String>("path")!!, call.argument<String>("mime") ?: "*/*")
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("open_failed", e.message, null)
                    }
                }
                "releaseUri" -> {
                    try {
                        contentResolver.releasePersistableUriPermission(Uri.parse(call.argument<String>("uri")!!), Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    } catch (_: Exception) { }
                    result.success(true)
                }
                "keepAwake" -> {
                    if (call.argument<Boolean>("on") == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        Thread {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message ?: e.toString(), null) }
            }
        }.start()
    }

    // ---------- Picking ----------

    private fun pickFiles(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "Picker already open", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, pickRequest)
        } catch (e: Exception) {
            pendingPick = null
            result.error("no_picker", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == treeRequest) {
            val r = pendingTree ?: return
            pendingTree = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) { r.success(null); return }
            try {
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            } catch (_: Exception) { }
            val name = DocumentsContract.getTreeDocumentId(uri).substringAfterLast(':').substringAfterLast('/').ifEmpty { "Folder" }
            r.success(mapOf("uri" to uri.toString(), "name" to name))
            return
        }
        if (requestCode != pickRequest) return
        val result = pendingPick ?: return
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        val uris = mutableListOf<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
        } else {
            data.data?.let { uris.add(it) }
        }
        Thread {
            val list = uris.map { uri ->
                try {
                    contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } catch (_: Exception) { }
                describe(uri)
            }
            main.post { result.success(list) }
        }.start()
    }

    private fun describe(uri: Uri): Map<String, Any?> {
        var name = "file"
        var size = -1L
        var modified = 0L
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val n = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val s = c.getColumnIndex(OpenableColumns.SIZE)
                val m = c.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                if (n >= 0 && !c.isNull(n)) name = c.getString(n)
                if (s >= 0 && !c.isNull(s)) size = c.getLong(s)
                if (m >= 0 && !c.isNull(m)) modified = c.getLong(m)
            }
        }
        return mapOf("uri" to uri.toString(), "name" to name, "size" to size, "modified" to modified)
    }

    private fun copyToCache(uriText: String, name: String): String {
        val dir = File(cacheDir, "uploads")
        dir.mkdirs()
        dir.listFiles()?.forEach { it.deleteRecursively() } // only one file is ever kept here
        val safe = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val sub = File(dir, System.currentTimeMillis().toString())
        sub.mkdirs()
        val out = File(sub, safe)
        contentResolver.openInputStream(Uri.parse(uriText)).use { input ->
            if (input == null) throw IllegalStateException("Cannot read file")
            out.outputStream().use { input.copyTo(it, 1024 * 1024) }
        }
        return out.absolutePath
    }

    // ---------- Saving and opening ----------

    private fun saveToDownloads(path: String, name: String, mime: String): String {
        val src = File(path)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/TirsoDrive")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Could not create file in Downloads")
            resolver.openOutputStream(uri).use { out ->
                FileInputStream(src).use { it.copyTo(out!!, 1024 * 1024) }
            }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "Download/TirsoDrive/$name"
        } else {
            // Older Android (e.g. Fire TV): app's own folder, no extra permission needed.
            val dir = File(getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "TirsoDrive")
            dir.mkdirs()
            val out = File(dir, name)
            src.copyTo(out, overwrite = true)
            return out.absolutePath
        }
    }

    // ---------- Folder sync (Storage Access Framework tree) ----------

    private fun listTree(treeText: String): List<Map<String, Any?>> {
        val tree = Uri.parse(treeText)
        val out = ArrayList<Map<String, Any?>>()
        fun walk(docId: String, prefix: String, depth: Int) {
            if (depth > 25) return
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId)
            val cols = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            contentResolver.query(children, cols, null, null, null)?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getString(0)
                    val name = c.getString(1) ?: continue
                    if (name.startsWith(".")) continue
                    val mime = c.getString(2) ?: ""
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        walk(id, "$prefix$name/", depth + 1)
                    } else {
                        out.add(mapOf(
                            "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                            "path" to "$prefix$name",
                            "size" to (if (c.isNull(3)) -1L else c.getLong(3)),
                            "modified" to (if (c.isNull(4)) 0L else c.getLong(4))))
                    }
                }
            }
        }
        walk(DocumentsContract.getTreeDocumentId(tree), "", 0)
        return out
    }

    /** Writes a downloaded file into the synced folder at rel ("Sub/Folder/name.ext"), creating subfolders. */
    private fun writeToTree(treeText: String, rel: String, src: String): Map<String, Any?> {
        val tree = Uri.parse(treeText)
        var parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val parts = rel.split('/').filter { it.isNotEmpty() }
        for (dir in parts.dropLast(1)) {
            parent = findChild(tree, parent, dir) ?: DocumentsContract.createDocument(contentResolver, parent, DocumentsContract.Document.MIME_TYPE_DIR, dir)
                ?: throw IllegalStateException("Cannot create folder $dir")
        }
        val name = parts.last()
        val existing = findChild(tree, parent, name)
        val target = existing ?: DocumentsContract.createDocument(contentResolver, parent, "application/octet-stream", name)
            ?: throw IllegalStateException("Cannot create $name")
        contentResolver.openOutputStream(target, "wt").use { out -> FileInputStream(File(src)).use { it.copyTo(out!!, 1024 * 1024) } }
        var size = File(src).length()
        var modified = System.currentTimeMillis()
        contentResolver.query(target, arrayOf(DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_LAST_MODIFIED), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                if (!c.isNull(0)) size = c.getLong(0)
                if (!c.isNull(1)) modified = c.getLong(1)
            }
        }
        return mapOf("size" to size, "modified" to modified)
    }

    private fun findChild(tree: Uri, parent: Uri, name: String): Uri? {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getDocumentId(parent))
        contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { c ->
            while (c.moveToNext()) if (c.getString(1) == name) return DocumentsContract.buildDocumentUriUsingTree(tree, c.getString(0))
        }
        return null
    }

    /** Opens the Android share menu for downloaded files (no extra copy). */
    private fun shareFiles(paths: List<String>, names: List<String>, mimes: List<String>) {
        // No copy: other apps read the downloaded file directly, under its TirsoDrive name.
        File(cacheDir, "share").deleteRecursively() // leftovers from older versions
        val uris = ArrayList<Uri>()
        paths.forEachIndexed { i, p -> uris.add(ShareProvider.uriFor(this, p, names[i])) }
        val distinct = mimes.toSet()
        val mime = when {
            distinct.size == 1 -> distinct.first()
            distinct.all { it.startsWith("image/") } -> "image/*"
            distinct.all { it.startsWith("video/") } -> "video/*"
            else -> "*/*"
        }
        val intent = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).apply { putExtra(Intent.EXTRA_STREAM, uris[0]) }
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).apply { putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris) }
        }
        intent.type = mime
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        intent.clipData = android.content.ClipData.newRawUri(null, uris[0]).also { c -> uris.drop(1).forEach { c.addItem(android.content.ClipData.Item(it)) } }
        main.post {
            startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
        }
    }

    private fun openFile(path: String, mime: String) {
        val uri = FileProvider.getUriForFile(this, "$packageName.files", File(path))
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
