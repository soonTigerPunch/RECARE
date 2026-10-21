package com.detabev.recare

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var reminders: MethodChannel? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var openUrgent = false

    override fun onCreate(savedInstanceState: Bundle?) {
        captureOpenIntent(intent)
        super.onCreate(savedInstanceState)
    }

    private fun captureOpenIntent(value: Intent?) {
        if (value?.getBooleanExtra(ReminderScheduler.EXTRA_OPEN_URGENT, false) == true || value?.action == ReminderScheduler.OPEN_URGENT) {
            openUrgent = true
            value?.removeExtra(ReminderScheduler.EXTRA_OPEN_URGENT)
            value?.action = Intent.ACTION_MAIN
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureOpenIntent(intent)
        if (openUrgent) reminders?.invokeMethod("openUrgent", null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        reminders = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.detabev.recare/reminders").also { channel ->
            channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        // Reading settings must preserve an inexact alarm that is already pending.
                        "loadSettings" -> result.success(ReminderScheduler.load(this).asMap())
                        "requestPermission" -> {
                            if (ReminderScheduler.permissionGranted(this)) result.success(true)
                            else if (Build.VERSION.SDK_INT >= 33) {
                                if (pendingPermission != null) result.error("permission_busy", "권한 요청을 진행 중이에요.", null)
                                else {
                                    pendingPermission = result
                                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
                                }
                            } else result.success(false)
                        }
                        "configure" -> {
                            val enabled = call.argument<Boolean>("enabled") ?: throw IllegalArgumentException("enabled")
                            val hour = call.argument<Int>("hour") ?: throw IllegalArgumentException("hour")
                            val minute = call.argument<Int>("minute") ?: throw IllegalArgumentException("minute")
                            ReminderScheduler.configure(this, ReminderConfiguration(enabled, hour, minute))
                            result.success(null)
                        }
                        "consumeOpenUrgent" -> { val pending = openUrgent; openUrgent = false; result.success(pending) }
                        else -> result.notImplemented()
                    }
                } catch (failure: Exception) {
                    result.error("reminder_failed", failure.message ?: "알림을 설정하지 못했어요.", null)
                }
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST) {
            val result = pendingPermission
            pendingPermission = null
            result?.success(ReminderScheduler.permissionGranted(this))
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        reminders?.setMethodCallHandler(null)
        reminders = null
        pendingPermission?.error("activity_closed", "권한 요청이 중단됐어요.", null)
        pendingPermission = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    companion object { private const val PERMISSION_REQUEST = 1900 }
}
