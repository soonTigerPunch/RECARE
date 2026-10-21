package com.detabev.recare

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import java.util.concurrent.Executors

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action !in setOf(ReminderScheduler.ALARM, Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED)) return
        val pending = goAsync()
        executor.execute {
            try {
                if (action == ReminderScheduler.ALARM) ReminderScheduler.deliver(context.applicationContext)
                else ReminderScheduler.reschedule(context.applicationContext)
            } catch (failure: Exception) {
                // A temporarily locked/migrating DB must not crash the receiving process.
                Log.w("RecareReminder", "Reminder could not be delivered/rescheduled", failure)
            } finally {
                pending.finish()
            }
        }
    }
    companion object {
        private val executor = Executors.newSingleThreadExecutor()
    }
}
