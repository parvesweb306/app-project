package xyz.alaminislam.parentalcontrol

import android.accessibilityservice.AccessibilityService
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import android.view.inputmethod.InputMethodManager

class GuardAccessibilityService : AccessibilityService() {

    private var lastLaunch = 0L

    private val emergencyPackages = listOf(
        "com.android.dialer",
        "com.google.android.dialer",
        "com.android.incallui",
        "com.android.phone",
        "com.android.server.telecom",
        "com.samsung.android.incallui",
        "com.samsung.android.dialer"
    )

    override fun onServiceConnected() {
        super.onServiceConnected()
        LockService.start(this)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        if (!LockController.isLocked(this)) return

        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName || isAllowed(pkg)) return

        val now = SystemClock.elapsedRealtime()
        if (now - lastLaunch < 600) return
        lastLaunch = now
        LockController.bringToFront(this)
    }

    private fun isAllowed(pkg: String): Boolean {
        if (emergencyPackages.any { pkg.startsWith(it) }) return true

        return try {
            val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
            imm.enabledInputMethodList.any { it.packageName == pkg }
        } catch (_: Exception) {
            false
        }
    }

    override fun onInterrupt() {}
}