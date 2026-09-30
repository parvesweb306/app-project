package com.example.parental_control_app
 
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
 
/**
 * Foreground service: app বন্ধ থাকলেও প্রতি ৫ সেকেন্ডে server এ lock status দেখে।
 */
class LockService : Service() {

    @Volatile
    private var running = false
    private var worker: Thread? = null

    companion object {
        private const val CHANNEL_ID = "child_guard_status"
        private const val NOTIF_ID = 4101
        private const val POLL_MS = 5000L

        fun start(ctx: Context) {
            val intent = Intent(ctx, LockService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ctx.startForegroundService(intent)
                } else {
                    ctx.startService(intent)
                }
            } catch (_: Exception) {
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {
        if (!running) {
            running = true
            worker = Thread { loop() }.also { it.start() }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        worker?.interrupt()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun loop() {
        while (running) {
            try {
                poll()
            } catch (_: InterruptedException) {
                return
            } catch (_: Exception) {
            }

            try {
                Thread.sleep(POLL_MS)
            } catch (_: InterruptedException) {
                return
            }
        }
    }

    private fun poll() {
        val prefs = LockController.prefs(this)
        val token = prefs.getString("device_token", null)
        val base = prefs.getString("base_url", null)

        if (token.isNullOrEmpty() || base.isNullOrEmpty()) return

        val protection = if (LockController.protectionOk(this)) 1 else 0
        val url = URL(
            base + "/devices/status/" +
                URLEncoder.encode(token, "UTF-8") +
                "?protection=" + protection
        )

        val conn = url.openConnection() as HttpURLConnection
        try {
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.requestMethod = "GET"
            conn.setRequestProperty("Accept", "application/json")

            if (conn.responseCode != 200) return

            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val locked = JSONObject(body).optBoolean("is_locked", false)

            LockController.apply(this, locked)
        } finally {
            conn.disconnect()
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            val ch = NotificationChannel(
                CHANNEL_ID,
                "Child Guard",
                NotificationManager.IMPORTANCE_MIN
            )
            nm.createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Child Guard চালু আছে")
            .setContentText("Parent এর সাথে সংযুক্ত")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .build()
    }
}