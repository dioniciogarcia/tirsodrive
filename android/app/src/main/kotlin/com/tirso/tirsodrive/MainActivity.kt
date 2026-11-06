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
import io.flutter.embedding.android.FlutterActivity
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
class MainActivity : FlutterActivity() {
    private val channelName = "tirsodrive/native"
    private val pickRequest = 4711
    private var pendingPick: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        TransferService.onTogglePause = { main.post { channel.invokeMethod("togglePause", null) } }
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
                "shareFiles" -> background(result) {
                    shareFiles(call.argument<List<String>>("paths")!!, call.argument<List<String>>("names")!!, call.argument<List<String>>("mimes")!!)
                    true
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

    /** Copies files to cache/share with their TirsoDrive names, then opens the Android share menu. */
    private fun shareFiles(paths: List<String>, names: List<String>, mimes: List<String>) {
        val dir = File(cacheDir, "share")
        dir.deleteRecursively()
        dir.mkdirs()
        val uris = ArrayList<Uri>()
        paths.forEachIndexed { i, p ->
            val safe = names[i].replace(Regex("[\\\\/:*?\"<>|]"), "_")
            val sub = File(dir, i.toString())
            sub.mkdirs()
            val out = File(sub, safe)
            File(p).copyTo(out, overwrite = true)
            uris.add(FileProvider.getUriForFile(this, "$packageName.files", out))
        }
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
