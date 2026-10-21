package com.detabev.recare

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Standalone JVM assertions: no Android runtime or external test dependency. */
fun main() {
    val seoul = ZoneId.of("Asia/Seoul")
    fun next(now: String, hour: Int, minute: Int, zone: ZoneId = seoul) =
        ReminderPolicy.nextAlarm(Instant.parse(now), zone, hour, minute)
    check(next("2026-10-21T09:00:00Z", 19, 0) == Instant.parse("2026-10-21T10:00:00Z"))
    check(next("2026-10-21T10:00:00Z", 19, 0) == Instant.parse("2026-10-22T10:00:00Z"))
    check(next("2026-10-21T23:00:00Z", 8, 15) == Instant.parse("2026-10-21T23:15:00Z"))
    // Spring DST gap: the nonexistent 02:30 moves to 03:30 on that local date.
    check(next("2026-03-08T05:00:00Z", 2, 30, ZoneId.of("America/New_York")) == Instant.parse("2026-03-08T07:30:00Z"))
    val milestones = ReminderPolicy.milestoneDates(LocalDate.parse("2026-10-21"))
    check(milestones == listOf("2026-10-21", "2026-10-22", "2026-10-24"))
    check("2026-10-20" !in milestones) // Expired inventory is not a milestone.
    check("2026-10-23" !in milestones) // Two days before expiry is not a milestone.
    check("2026-10-25" !in milestones)
    check(ReminderPolicy.milestoneDates(LocalDate.parse("2026-12-30")) ==
        listOf("2026-12-30", "2026-12-31", "2027-01-02"))
    check(ReminderPolicy.milestoneDates(LocalDate.parse("2028-02-28")) ==
        listOf("2028-02-28", "2028-02-29", "2028-03-02"))
    check(ReminderPolicy.canDeliver("2026-10-21", null))
    check(!ReminderPolicy.canDeliver("2026-10-21", "2026-10-21"))
    check(!ReminderPolicy.canDeliver("2026-10-20", "2026-10-21"))
    check(ReminderPolicy.canDeliver("2026-10-22", "2026-10-21"))
    println("ReminderPolicy: 14 assertions passed")
}
