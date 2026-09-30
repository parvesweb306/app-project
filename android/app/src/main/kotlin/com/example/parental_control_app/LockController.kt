package xyz.alaminislam.parentalcontrol

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.os.UserManager
import android.provider.Settings

object LockController {

    private const val PREFS = "LockPrefs"
    private const val LOCKED_KEY = "is_locked"

    fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun devicePrefs(ctx: Context) =
        ctx.createDeviceProtectedStorageContext()
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isLocked(ctx: Context): Boolean {
        val userManager = ctx.getSystemService(Context.USER_SERVICE) as UserManager
        if (!userManager.isUserUnlocked) {
            return devicePrefs(ctx).getBoolean(LOCKED_KEY, false)
        }

        val regular = prefs(ctx)
        if (regular.contains(LOCKED_KEY)) {
            val value = regular.getBoolean(LOCKED_KEY, false)
            devicePrefs(ctx).edit().putBoolean(LOCKED_KEY, value).apply()
            return value
        }
        return devicePrefs(ctx).getBoolean(LOCKED_KEY, false)
    }

    fun setLocked(ctx: Context, value: Boolean) {
        prefs(ctx).edit().putBoolean(LOCKED_KEY, value).apply()
        devicePrefs(ctx).edit().putBoolean(LOCKED_KEY, value).apply()
    }

    private fun adminComponent(ctx: Context) =
        ComponentName(ctx, DeviceAdminReceiver::class.java)

    fun isAdminActive(ctx: Context): Boolean {
        val dpm = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE)
            as DevicePolicyManager
        return dpm.isAdminActive(adminComponent(ctx))
    }

    fun isDeviceOwner(ctx: Context): Boolean {
        val dpm = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE)
            as DevicePolicyManager
        return dpm.isDeviceOwnerApp(ctx.packageName)
    }

    fun prepareLockTask(ctx: Context): Boolean {
        if (!isDeviceOwner(ctx)) return false

        return try {
            val dpm = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE)
                as DevicePolicyManager
            dpm.setLockTaskPackages(adminComponent(ctx), arrayOf(ctx.packageName))
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                dpm.setLockTaskFeatures(
                    adminComponent(ctx),
                    DevicePolicyManager.LOCK_TASK_FEATURE_NONE
                )
            }
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                dpm.setKeyguardDisabled(adminComponent(ctx), true)
                dpm.setStatusBarDisabled(adminComponent(ctx), true)
            }
            true
        } catch (_: SecurityException) {
            false
        }
    }

    fun clearLockTaskRestrictions(ctx: Context) {
        if (!isDeviceOwner(ctx)) return

        try {
            val dpm = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE)
                as DevicePolicyManager
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                dpm.setStatusBarDisabled(adminComponent(ctx), false)
                dpm.setKeyguardDisabled(adminComponent(ctx), false)
            }
        } catch (_: SecurityException) {
        }
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
        isDeviceOwner(ctx) && isAccessibilityOn(ctx) && isOverlayGranted(ctx)

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

    fun bringToFront(ctx: Context) {
        try {
            val intent = Intent(ctx, MainActivity::class.java)
            intent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION
            )
            ctx.startActivity(intent)
        } catch (_: Exception) {
        }
    }

    private fun isScreenOn(ctx: Context): Boolean {
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isInteractive
    }

    fun apply(ctx: Context, serverLocked: Boolean) {
        val was = isLocked(ctx)

        if (serverLocked) {
            if (!was) {
                setLocked(ctx, true)
                bringToFront(ctx)
            } else if (isScreenOn(ctx) && !MainActivity.visible) {
                bringToFront(ctx)
            }
        } else if (was) {
            setLocked(ctx, false)
        }
    }
}