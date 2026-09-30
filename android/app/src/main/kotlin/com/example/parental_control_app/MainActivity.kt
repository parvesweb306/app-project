package xyz.alaminislam.parentalcontrol

import android.Manifest
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.View
import android.view.WindowManager
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        @Volatile
        var visible = false
    }

    private val channelName = "device_admin_channel"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (LockController.isLocked(this)) {
            enforceLockState()
        }
    }

    override fun onResume() {
        super.onResume()
        visible = true
        enforceLockState()
    }

    override fun onPause() {
        visible = false
        super.onPause()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (LockController.isLocked(this)) {
            LockController.bringToFront(this)
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && LockController.isLocked(this)) {
            enforceLockState()
        }
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (LockController.isLocked(this)) {
            enforceLockState()
            return
        }
        super.onBackPressed()
    }

    @Suppress("DEPRECATION")
    private fun enforceLockState() {
        val locked = LockController.isLocked(this)
        applyLockUi(locked)

        val activityManager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        val inLockTask = activityManager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE

        if (locked) {
            val canUseLockTask = LockController.prepareLockTask(this)
            if (canUseLockTask && !inLockTask) {
                try {
                    startLockTask()
                } catch (_: SecurityException) {
                }
            }
        } else if (inLockTask) {
            try {
                stopLockTask()
            } catch (_: SecurityException) {
            }
            LockController.clearLockTaskRestrictions(this)
        }
    }

    @Suppress("DEPRECATION")
    private fun applyLockUi(locked: Boolean) {
        if (locked) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            window.decorView.systemUiVisibility = 0
        }
    }

    private fun pairingCodeFromUri(rawUri: String?): String? {
        val uri = rawUri?.let(Uri::parse) ?: return null
        val code = uri.getQueryParameter("pairing_code")
            ?: uri.getQueryParameter("family_invite")
            ?: uri.getQueryParameter("code")

        return code
            ?.trim()
            ?.uppercase()
            ?.takeIf { it.matches(Regex("^(?:[A-Z0-9]{6}|[A-Z0-9]{32})$")) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "getDeviceName" -> {
                    val manufacturer = Build.MANUFACTURER.orEmpty().trim()
                    val model = Build.MODEL.orEmpty().trim()
                    val deviceName = listOf(manufacturer, model)
                        .distinct()
                        .filter { it.isNotBlank() }
                        .joinToString(" ")
                        .take(100)
                    result.success(deviceName)
                }

                "getInstallPairingCode" -> {
                    val directCode = pairingCodeFromUri(intent?.dataString)
                    if (directCode != null) {
                        result.success(directCode)
                    } else {
                        val referrerClient =
                            InstallReferrerClient.newBuilder(this).build()
                        try {
                            referrerClient.startConnection(
                                object : InstallReferrerStateListener {
                                    override fun onInstallReferrerSetupFinished(
                                        responseCode: Int
                                    ) {
                                        val code = if (
                                            responseCode == InstallReferrerClient.InstallReferrerResponse.OK
                                        ) {
                                            try {
                                                val referrer = referrerClient
                                                    .installReferrer
                                                    .installReferrer
                                                pairingCodeFromUri(
                                                    "https://referrer.invalid/?$referrer"
                                                )
                                            } catch (_: Exception) {
                                                null
                                            }
                                        } else {
                                            null
                                        }

                                        referrerClient.endConnection()
                                        result.success(code)
                                    }

                                    override fun onInstallReferrerServiceDisconnected() {
                                        result.success(null)
                                    }
                                }
                            )
                        } catch (_: Exception) {
                            referrerClient.endConnection()
                            result.success(null)
                        }
                    }
                }

                // ---------- Device Admin ----------
                "isAdminActive" ->
                    result.success(LockController.isAdminActive(this))

                "requestAdmin" -> {
                    if (!LockController.isAdminActive(this)) {
                        val intent = Intent(
                            DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN
                        )
                        intent.putExtra(
                            DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                            ComponentName(this, DeviceAdminReceiver::class.java)
                        )
                        intent.putExtra(
                            DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                            "Screen lock করতে এবং app uninstall আটকাতে এই অনুমতি দরকার।"
                        )
                        startActivity(intent)
                    }
                    result.success(true)
                }

                // ---------- Overlay ----------
                "isOverlayGranted" ->
                    result.success(LockController.isOverlayGranted(this))

                "requestOverlay" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                    startActivity(intent)
                    result.success(true)
                }

                // ---------- Accessibility ----------
                "isAccessibilityEnabled" ->
                    result.success(LockController.isAccessibilityOn(this))

                "requestAccessibility" -> {
                    val serviceSettingsIntent = Intent(
                        "android.settings.ACCESSIBILITY_DETAILS_SETTINGS"
                    ).putExtra(
                        Intent.EXTRA_COMPONENT_NAME,
                        ComponentName(this, GuardAccessibilityService::class.java)
                    )

                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            startActivity(serviceSettingsIntent)
                        } else {
                            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        }
                    } catch (_: Exception) {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    }
                    result.success(true)
                }

                "openAppDetails" -> {
                    val intent = Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName")
                    )
                    startActivity(intent)
                    result.success(true)
                }

                // ---------- Battery ----------
                "isBatteryIgnored" -> {
                    val pm = getSystemService(Context.POWER_SERVICE)
                        as PowerManager
                    result.success(
                        pm.isIgnoringBatteryOptimizations(packageName)
                    )
                }

                "requestBattery" -> {
                    try {
                        val intent = Intent(
                            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                    } catch (_: Exception) {
                        startActivity(
                            Intent(
                                Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                            )
                        )
                    }
                    result.success(true)
                }

                // ---------- Notification ----------
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(
                            Manifest.permission.POST_NOTIFICATIONS
                        ) != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            101
                        )
                    }
                    result.success(true)
                }

                // ---------- Service ----------
                "startService" -> {
                    LockService.start(this)
                    result.success(true)
                }

                // ---------- Lock state ----------
                "isNativeLocked" ->
                    result.success(LockController.isLocked(this))

                "setNativeLocked" -> {
                    val value = call.argument<Boolean>("value") ?: false
                    LockController.setLocked(this, value)
                    enforceLockState()
                    result.success(true)
                }

                // ---------- Pairing data ----------
                "saveDeviceToken" -> {
                    val token = call.argument<String>("token")
                    val baseUrl = call.argument<String>("base_url")
                    val editor = LockController.prefs(this).edit()
                    if (!token.isNullOrEmpty()) {
                        editor.putString("device_token", token)
                    }
                    if (!baseUrl.isNullOrEmpty()) {
                        editor.putString("base_url", baseUrl)
                    }
                    editor.apply()
                    result.success(true)
                }

                "setPaired" -> {
                    val value = call.argument<Boolean>("value") ?: false
                    LockController.prefs(this)
                        .edit().putBoolean("is_paired", value).apply()
                    result.success(true)
                }

                "isPaired" ->
                    result.success(
                        LockController.prefs(this)
                            .getBoolean("is_paired", false)
                    )

                else -> result.notImplemented()
            }
        }
    }
}