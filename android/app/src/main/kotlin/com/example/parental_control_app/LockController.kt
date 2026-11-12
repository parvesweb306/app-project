package xyz.alaminislam.parentalcontrol

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.os.UserManager
import android.provider.Settings
import java.security.MessageDigest

object LockController {

    private const val PREFS = "LockPrefs"
    private const val LOCKED_KEY = "is_locked"
    private const val CODE_HASH_KEY = "unlock_code_hash"

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

    // ---------- LIFETIME UNLOCK CODE ----------

    private fun sha256(text: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(text.toByteArray())
            .joinToString("") { "%02x".format(it) }

    fun generateUnlockCode(ctx: Context): String {
        val code = (100000000..999999999).random().toString()
        devicePrefs(ctx).edit().putString(CODE_HASH_KEY, sha256(code)).apply()
        return code
    }

    fun verifyAndUnlock(ctx: Context, code: String): Boolean {
        if (code.isBlank()) return false
        val storedHash = devicePrefs(ctx).getString(CODE_HASH_KEY, null)
            ?: return false

        if (sha256(code.trim()) != storedHash) return false

        resetLock(ctx)
        return true
    }

    fun forceUnlock(ctx: Context) {
        resetLock(ctx)
    }

    private fun resetLock(ctx: Context) {
        devicePrefs(ctx).edit()
            .remove(CODE_HASH_KEY)
            .putBoolean(LOCKED_KEY, false)
            .apply()
        prefs(ctx).edit()
            .remove(CODE_HASH_KEY)
            .putBoolean(LOCKED_KEY, false)
            .apply()
    }

    // ---------- DEVICE ADMIN / OWNER ----------

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

            // App uninstall বন্ধ
            try {
                dpm.setUninstallBlocked(adminComponent(ctx), ctx.packageName, true)
            } catch (_: Exception) {
            }

            // ==========================================================
            // নতুন: Settings থেকে factory reset ও safe mode বন্ধ
            // ==========================================================
            try {
                dpm.addUserRestriction(
                    adminComponent(ctx),
                    UserManager.DISALLOW_FACTORY_RESET
                )
                dpm.addUserRestriction(
                    adminComponent(ctx),
                    UserManager.DISALLOW_SAFE_BOOT
                )
            } catch (_: Exception) {
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

            // Unlock হলে reset আবার allowed — normal phone হয়ে যাবে
            try {
                dpm.clearUserRestriction(
                    adminComponent(ctx),
                    UserManager.DISALLOW_FACTORY_RESET
                )
                dpm.clearUserRestriction(
                    adminComponent(ctx),
                    UserManager.DISALLOW_SAFE_BOOT
                )
            } catch (_: Exception) {
            }
        } catch (_: SecurityException) {
        }
    }

    // ---------- PERMISSIONS ----------

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
        if (serverLocked && isLocked(ctx) && isScreenOn(ctx) && !MainActivity.visible) {
            bringToFront(ctx)
        }
    }
}
