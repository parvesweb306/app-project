package com.example.parental_control_app

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.provider.Settings
 
object LockController {

    private const val PREFS = "LockPrefs"

    fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isLocked(ctx: Context): Boolean =
        prefs(ctx).getBoolean("is_locked", false)

    fun setLocked(ctx: Context, value: Boolean) {
        prefs(ctx).edit().putBoolean("is_locked", value).apply()
    }

    private fun adminComponent(ctx: Context) =
        ComponentName(ctx, DeviceAdminReceiver::class.java)

    fun isAdminActive(ctx: Context): Boolean {
        val dpm = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE)
            as DevicePolicyManager
        return dpm.isAdminActive(adminComponent(ctx))
    }

    fun isAccessibilityOn(ctx: Context): Boolean {
        val enabled = Settings.Secure.getString(
            ctx.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val cn = ComponentName(ctx, GuardAccessibilityService::class.java)
        val full = cn.flattenToString()
        val short = cn.flattenToShortString()

        return enabled.split(':').any {
            it.equals(full, true) || it.equals(short, true)
        }
    }

    fun isOverlayGranted(ctx: Context): Boolean =
        Settings.canDrawOverlays(ctx)

    fun protectionOk(ctx: Context): Boolean =
        isAdminActive(ctx) && isAccessibilityOn(ctx) && isOverlayGranted(ctx)

    /** Screen সাথে সাথে lock করে (Device Admin থাকলে) */
    fun lockScreenNow(ctx: Context) {
        try {
            val dpm = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE)
                as DevicePolicyManager
            if (dpm.isAdminActive(adminComponent(ctx))) {
                dpm.lockNow()
            }
        } catch (_: Exception) {
        }
    }

    /** Child Guard এর lock screen সবার উপরে আনে */
    fun bringToFront(ctx: Context) {
        try {
            val intent = Intent(ctx, MainActivity::class.java)
            intent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            ctx.startActivity(intent)
        } catch (_: Exception) {
        }
    }

    private fun isScreenOn(ctx: Context): Boolean {
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isInteractive
    }

    /** Server থেকে পাওয়া lock অবস্থা প্রয়োগ করে */
    fun apply(ctx: Context, serverLocked: Boolean) {
        val was = isLocked(ctx)

        if (serverLocked) {
            if (!was) {
                setLocked(ctx, true)
                if (isAdminActive(ctx)) {
                    lockScreenNow(ctx)
                } else {
                    bringToFront(ctx)
                }
            } else if (isScreenOn(ctx) && !MainActivity.visible) {
                // backup: accessibility বন্ধ থাকলেও lock screen ফিরিয়ে আনবে
                bringToFront(ctx)
            }
        } else if (was) {
            setLocked(ctx, false)
        }
    }
}