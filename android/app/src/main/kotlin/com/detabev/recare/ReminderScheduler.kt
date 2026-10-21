package com.detabev.recare

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

internal data class ReminderConfiguration(val enabled: Boolean, val hour: Int, val minute: Int) {
    fun asMap(): Map<String, Any> = mapOf("enabled" to enabled, "hour" to hour, "minute" to minute)
}

internal object ReminderScheduler {
    const val OPEN_URGENT = "com.detabev.recare.OPEN_URGENT"
    const val EXTRA_OPEN_URGENT = "open_urgent"
    const val ALARM = "com.detabev.recare.DAILY_DIGEST"
    private const val CHANNEL = "expiry_digest"
    private const val NOTIFICATION_ID = 1900
    private const val REQUEST_CODE = 1900
    private fun prefs(context: Context) = context.getSharedPreferences("daily_expiry_reminder", Context.MODE_PRIVATE)
    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)

    fun ensureChannel(context: Context) {
        manager(context).createNotificationChannel(
            NotificationChannel(CHANNEL, "소비기한 알림", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "소비기한 3일 전, 1일 전, 당일에 남은 식재료를 하루 한 번 알려드려요."
            }
        )
    }

    fun permissionGranted(context: Context): Boolean {
        ensureChannel(context)
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        return manager(context).areNotificationsEnabled() &&
            manager(context).getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
    }

    private fun stored(context: Context): ReminderConfiguration {
        val preferences = prefs(context)
        return ReminderConfiguration(
            preferences.getBoolean("enabled", false),
            preferences.getInt("hour", 19).coerceIn(0, 23),
            preferences.getInt("minute", 0).coerceIn(0, 59)
        )
    }

    private fun persist(context: Context, value: ReminderConfiguration) {
        check(prefs(context).edit().putBoolean("enabled", value.enabled)
            .putInt("hour", value.hour).putInt("minute", value.minute).commit()) { "설정을 저장하지 못했어요." }
    }

    @Synchronized
    fun load(context: Context): ReminderConfiguration {
        val value = stored(context)
        if (value.enabled && !permissionGranted(context)) {
            val disabled = value.copy(enabled = false)
            persist(context, disabled)
            cancel(context)
            return disabled
        }
        return value
    }

    @Synchronized
    fun configure(context: Context, value: ReminderConfiguration) {
        require(value.hour in 0..23 && value.minute in 0..59) { "알림 시간을 확인해주세요." }
        if (value.enabled) check(permissionGranted(context)) { "알림 권한을 허용해주세요." }
        val previous = stored(context)
        try {
            persist(context, value)
            if (value.enabled) schedule(context, value) else cancel(context)
        } catch (failure: Exception) {
            // Surface the failure and restore the prior persisted/scheduled state.
            try {
                persist(context, previous)
                if (previous.enabled && permissionGranted(context)) schedule(context, previous) else cancel(context)
            } catch (rollbackFailure: Exception) {
                // If rollback itself fails, force a truthful disabled state when possible.
                try { persist(context, previous.copy(enabled = false)) } catch (_: Exception) { }
                try { cancel(context) } catch (_: Exception) { }
                failure.addSuppressed(rollbackFailure)
            }
            throw failure
        }
    }

    private fun alarmIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, REQUEST_CODE, Intent(context, ReminderReceiver::class.java).setAction(ALARM),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    private fun schedule(context: Context, value: ReminderConfiguration) {
        val next = ReminderPolicy.nextAlarm(Instant.now(), ZoneId.systemDefault(), value.hour, value.minute)
        // This API is deliberately inexact and does not need exact-alarm permission.
        context.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP, next.toEpochMilli(), alarmIntent(context)
        )
    }

    private fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java).cancel(alarmIntent(context))
        manager(context).cancel(NOTIFICATION_ID)
    }

    @Synchronized
    fun reschedule(context: Context) {
        val value = load(context)
        if (value.enabled) schedule(context, value) else cancel(context)
    }

    private data class Digest(val count: Int, val firstName: String)

    private fun currentDigest(context: Context, today: LocalDate): Digest? {
        // sqflite's Android database directory is Context.getDatabasePath(...).parent.
        // Opening read-only neither creates an empty database nor performs a migration.
        val file = context.getDatabasePath("recare.db")
        if (!file.exists()) return null
        SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY).use { database ->
            // Flutter owns schema migrations. An alarm may run before its first launch
            // after an update, when the check-in table has not been created yet.
            val hasCheckIns = database.rawQuery(
                "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'expiry_check_ins'",
                null
            ).use { it.moveToFirst() }
            val acknowledgedFilter = if (hasCheckIns)
                " AND NOT EXISTS (SELECT 1 FROM expiry_check_ins WHERE food_id = foods.id AND expiry = foods.expiry AND day = ?)"
                else ""
            val arguments = ReminderPolicy.milestoneDates(today).toMutableList()
            if (hasCheckIns) arguments.add(today.toString())
            database.rawQuery(
                "SELECT name FROM foods WHERE remaining > 0 AND expiry IN (?, ?, ?)" +
                    acknowledgedFilter + " ORDER BY expiry, name",
                arguments.toTypedArray()
            ).use { cursor ->
                if (!cursor.moveToFirst()) return null
                return Digest(cursor.count, cursor.getString(0))
            }
        }
    }

    @Synchronized
    fun deliver(context: Context) {
        val value = load(context)
        if (!value.enabled) return
        // Schedule the next occurrence first, even when today's inventory is empty.
        schedule(context, value)
        val now = Instant.now().atZone(ZoneId.systemDefault())
        if (now.toLocalTime().isBefore(java.time.LocalTime.of(value.hour, value.minute))) return
        val today = now.toLocalDate()
        val preferences = prefs(context)
        if (!ReminderPolicy.canDeliver(today.toString(), preferences.getString("last_delivered", null))) return
        val digest = currentDigest(context, today) ?: return
        if (!permissionGranted(context)) { load(context); return }
        val body = if (digest.count == 1) "${digest.firstName}: 앱을 열어 소비한 수량을 알려주세요."
            else "${digest.firstName} 외 ${digest.count - 1}개: 앱을 열어 소비한 수량을 알려주세요."
        val open = PendingIntent.getActivity(context, REQUEST_CODE,
            Intent(context, MainActivity::class.java).setAction(OPEN_URGENT)
                .putExtra(EXTRA_OPEN_URGENT, true)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("소비기한이 임박했어요! 얼마나 소비하셨나요?")
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .build()
        // Reserve the day durably before posting, preventing retry duplicates.
        check(preferences.edit().putString("last_delivered", today.toString()).commit())
        manager(context).notify(NOTIFICATION_ID, notification)
    }
}
