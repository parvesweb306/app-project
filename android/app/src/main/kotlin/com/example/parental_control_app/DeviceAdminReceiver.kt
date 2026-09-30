package xyz.alaminislam.parentalcontrol

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

class DeviceAdminReceiver : DeviceAdminReceiver() {

    override fun onDisableRequested(
        context: Context,
        intent: Intent
    ): CharSequence {
        return "এটা বন্ধ করলে Child Guard এর সুরক্ষা কমে যাবে।"
    }
}