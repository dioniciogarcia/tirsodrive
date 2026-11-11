package com.tirso.tirsodrive.wear

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** Update check for the watch. Reads GitHub Releases; the install step needs the watch to allow it (many Wear OS watches don't). */
object Upd {
    private const val REPO = "dioniciogarcia/tirsodrive"
    private const val ASSET = "TirsoDrive-Wear.apk"

    var installed by mutableStateOf("")
    var latest by mutableStateOf("")
    var status by mutableStateOf("")   // "", checking, uptodate, available, downloading, installing, error:<text>
    var progress by mutableStateOf(0f)
    private var url: String? = null
    private var size = 0L

    val available get() = latest.isNotEmpty() && compare(latest, installed) > 0

    fun compare(a: String, b: String): Int {
        fun p(v: String) = v.trim().trimStart('v', 'V').split('+', '-').first().split('.').map { it.toIntOrNull() ?: 0 }
        val x = p(a); val y = p(b)
        for (i in 0 until maxOf(x.size, y.size)) {
            val u = x.getOrElse(i) { 0 }; val v = y.getOrElse(i) { 0 }
            if (u != v) return u.compareTo(v)
        }
        return 0
    }

    suspend fun check(ctx: Context) {
        installed = ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName ?: ""
        status = "checking"
        try {
            val j = withContext(Dispatchers.IO) {
                val c = URL("https://api.github.com/repos/$REPO/releases/latest").openConnection() as HttpURLConnection
                c.connectTimeout = 12000; c.readTimeout = 20000
                c.setRequestProperty("Accept", "application/vnd.github+json"); c.setRequestProperty("User-Agent", "TirsoDrive-watch")
                if (c.responseCode != 200) throw Exception("GitHub ${c.responseCode}")
                JSONObject(c.inputStream.bufferedReader().readText())
            }
            latest = j.optString("tag_name").trimStart('v', 'V')
            val assets = j.optJSONArray("assets")
            url = null
            for (i in 0 until (assets?.length() ?: 0)) {
                val a = assets!!.getJSONObject(i)
                if (a.optString("name") == ASSET && a.optString("browser_download_url").startsWith("https://github.com/$REPO/releases/download/")) {
                    url = a.optString("browser_download_url"); size = a.optLong("size")
                }
            }
            status = if (available && url != null) "available" else "uptodate"
        } catch (e: Exception) { status = "error:" + (e.message ?: "network") }
    }

    suspend fun install(ctx: Context) {
        val u = url ?: return
        try {
            status = "downloading"; progress = 0f
            val dir = File(ctx.cacheDir, "updates").apply { deleteRecursively(); mkdirs() }
            val apk = File(dir, ASSET)
            withContext(Dispatchers.IO) {
                val c = URL(u).openConnection() as HttpURLConnection
                c.connectTimeout = 15000; c.readTimeout = 30000
                if (c.responseCode != 200) throw Exception("download ${c.responseCode}")
                val total = if (c.contentLengthLong > 0) c.contentLengthLong else size
                var got = 0L
                c.inputStream.use { i -> apk.outputStream().use { o ->
                    val buf = ByteArray(64 * 1024)
                    while (true) { val n = i.read(buf); if (n < 0) break; o.write(buf, 0, n); got += n; if (total > 0) progress = got.toFloat() / total }
                } }
                if (size > 0 && got != size) throw Exception("incomplete download")
            }
            val pi = ctx.packageManager.getPackageArchiveInfo(apk.path, 0) ?: throw Exception("not a valid APK")
            if (pi.packageName != ctx.packageName) throw Exception("APK is for another app")
            if (pi.longVersionCode <= ctx.packageManager.getPackageInfo(ctx.packageName, 0).longVersionCode) throw Exception("APK is not newer")
            if (Build.VERSION.SDK_INT >= 26 && !ctx.packageManager.canRequestPackageInstalls()) {
                try { ctx.startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, android.net.Uri.parse("package:${ctx.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: Exception) {}
                status = "error:permission"; return
            }
            status = "installing"
            val inst = ctx.packageManager.packageInstaller
            val id = inst.createSession(PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL))
            inst.openSession(id).use { s ->
                apk.inputStream().use { i -> s.openWrite("app", 0, apk.length()).use { o -> i.copyTo(o); s.fsync(o) } }
                val action = "com.tirso.tirsodrive.wear.INSTALL_RESULT"
                ctx.registerReceiver(object : BroadcastReceiver() {
                    override fun onReceive(c: Context, i: Intent) {
                        when (i.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)) {
                            PackageInstaller.STATUS_PENDING_USER_ACTION ->
                                @Suppress("DEPRECATION") (i.getParcelableExtra<Intent>(Intent.EXTRA_INTENT))?.let { c.startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                            PackageInstaller.STATUS_SUCCESS -> {}
                            else -> { status = "error:" + (i.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "install failed"); try { c.unregisterReceiver(this) } catch (_: Exception) {} }
                        }
                    }
                }, IntentFilter(action), Context.RECEIVER_NOT_EXPORTED)
                val pending = PendingIntent.getBroadcast(ctx, id, Intent(action).setPackage(ctx.packageName), PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
                s.commit(pending.intentSender)
            }
        } catch (e: Exception) { status = "error:" + (e.message ?: "failed") }
    }
}
