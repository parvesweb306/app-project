package xyz.alaminislam.parentalcontrol

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper

class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) return

        LockService.start(context)

        if (LockController.isLocked(context)) {
            LockController.bringToFront(context)
            Handler(Looper.getMainLooper()).postDelayed({
                LockController.bringToFront(context)
            }, 1000)
        }
    }
}