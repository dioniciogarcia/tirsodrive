package com.tirso.tirsodrive

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * Keeps TirsoDrive running while files transfer, even with the screen locked or another app open.
 * Shows the progress notification; its Pause/Resume button is passed back to the app.
 */
class TransferService : Service() {
    companion object {
        const val CHANNEL_ID = "transfers"
        const val NOTIF_ID = 2207
        const val ACTION_UPDATE = "com.tirso.tirsodrive.UPDATE"
        const val ACTION_STOP = "com.tirso.tirsodrive.STOP"
        const val ACTION_TOGGLE = "com.tirso.tirsodrive.TOGGLE_PAUSE"

        /** Set by MainActivity: called when the notification's Pause/Resume button is tapped. */
        var onTogglePause: (() -> Unit)? = null
        var running = false
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Transfers", NotificationManager.IMPORTANCE_LOW))
        }
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "TirsoDrive:transfers").apply { setReferenceCounted(false); acquire(6 * 60 * 60 * 1000L) }
        try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "TirsoDrive:wifi").apply { setReferenceCounted(false); acquire() }
        } catch (_: Exception) { }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForegroundCompat()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_TOGGLE -> {
                onTogglePause?.invoke()
                return START_NOT_STICKY
            }
        }
        val title = intent?.getStringExtra("title") ?: "TirsoDrive"
        val text = intent?.getStringExtra("text") ?: ""
        val progress = intent?.getIntExtra("progress", -1) ?: -1
        val paused = intent?.getBooleanExtra("paused", false) ?: false
        val button = intent?.getStringExtra("button") ?: if (paused) "Resume" else "Pause"
        val n = build(title, text, progress, paused, button)
        if (!running) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIF_ID, n)
            }
            running = true
        } else {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIF_ID, n)
        }
        return START_NOT_STICKY
    }

    private fun build(title: String, text: String, progress: Int, paused: Boolean, button: String): Notification {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), flags)
        val toggle = PendingIntent.getService(this, 1, Intent(this, TransferService::class.java).setAction(ACTION_TOGGLE), flags)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle(title)
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(open)
            .setProgress(100, progress.coerceIn(0, 100), progress < 0 && !paused)
            .addAction(0, button, toggle)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
        running = false
    }

    override fun onDestroy() {
        running = false
        try { wakeLock?.release() } catch (_: Exception) { }
        try { wifiLock?.release() } catch (_: Exception) { }
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // App swiped away from recents: the app stops, so remove the notification.
        // Unfinished uploads are remembered and continue the next time TirsoDrive opens.
        stopForegroundCompat()
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 15 limits background data-sync time; stop cleanly instead of crashing.
        stopForegroundCompat()
        stopSelf()
    }
}
