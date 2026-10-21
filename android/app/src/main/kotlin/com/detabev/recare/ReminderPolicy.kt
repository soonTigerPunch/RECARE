package com.detabev.recare

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

internal object ReminderPolicy {
    fun nextAlarm(now: Instant, zone: ZoneId, hour: Int, minute: Int): Instant {
        val date = now.atZone(zone).toLocalDate()
        var next = date.atTime(hour, minute).atZone(zone).toInstant()
        if (!next.isAfter(now)) next = date.plusDays(1).atTime(hour, minute).atZone(zone).toInstant()
        return next
    }

    fun milestoneDates(today: LocalDate): List<String> =
        listOf(today, today.plusDays(1), today.plusDays(3)).map { it.toString() }

    // Also suppress a repeat after moving the clock/timezone back across midnight.
    fun canDeliver(today: String, lastDelivered: String?): Boolean =
        lastDelivered == null || today > lastDelivered
}
