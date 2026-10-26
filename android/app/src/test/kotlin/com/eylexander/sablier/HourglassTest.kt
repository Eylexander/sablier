package com.eylexander.sablier

import android.app.usage.UsageEvents.Event.ACTIVITY_PAUSED
import android.app.usage.UsageEvents.Event.ACTIVITY_RESUMED
import android.app.usage.UsageEvents.Event.SCREEN_NON_INTERACTIVE
import org.junit.Assert.assertEquals
import org.junit.Test

// cd android && ./gradlew :app:testDebugUnitTest
class HourglassTest {
    private val min = 60_000L
    private val hour = 60 * min
    private val insta = setOf("com.instagram.android")

    @Test
    fun usedClipsToTheWindow() {
        val s = listOf(Session(0, 10 * min), Session(50 * min, 55 * min))
        assertEquals(15 * min, Hourglass.used(s, 0, hour))
        assertEquals(7 * min, Hourglass.used(s, 5 * min, 52 * min)) // 5 of the first, 2 of the second
    }

    @Test
    fun budgetComesBackAWindowLater() {
        // 5 min used from 10:00 to 10:05 (in minutes since 9:30): with 5 min/h, a full minute is free at 11:01.
        val s = listOf(Session(30 * min, 35 * min))
        val now = 36 * min
        val at = Hourglass.freeAt(s, 5 * min, hour, min, now)
        assertEquals((91 * min).toDouble(), at.toDouble(), 1000.0)
        assertEquals(now, Hourglass.freeAt(s, 10 * min, hour, min, now)) // budget not spent: free now
    }

    @Test
    fun sessionsFromEvents() {
        val events = sequenceOf(
            Triple(ACTIVITY_PAUSED, "com.instagram.android", 2 * min), // was open when the window started
            Triple(ACTIVITY_RESUMED, "com.whatsapp", 3 * min),
            Triple(ACTIVITY_RESUMED, "com.instagram.android", 10 * min),
            Triple(ACTIVITY_RESUMED, "com.whatsapp", 12 * min), // switched without a pause event
            Triple(ACTIVITY_RESUMED, "com.instagram.android", 20 * min),
            Triple(SCREEN_NON_INTERACTIVE, "android", 21 * min),
            Triple(ACTIVITY_RESUMED, "com.instagram.android", 30 * min), // still on screen
        )
        val s = Hourglass.sessions(events, insta, 0, 31 * min)
        assertEquals(listOf(Session(0, 2 * min), Session(10 * min, 12 * min), Session(20 * min, 21 * min), Session(30 * min, 31 * min)), s)
    }

    @Test
    fun frontFollowsTheEvents() {
        val events = sequenceOf(
            Triple(ACTIVITY_RESUMED, "com.whatsapp", 1000L), // seen by the last poll
            Triple(ACTIVITY_RESUMED, "com.instagram.android", 3000L),
            Triple(ACTIVITY_PAUSED, "com.instagram.android", 4000L),
        )
        val f = Hourglass.front(events, "com.whatsapp", 2000)
        assertEquals("com.instagram.android", f.pkg)
        assertEquals(4000L, f.seen)
        assertEquals(true, f.changed)
        assertEquals(false, Hourglass.front(events, "com.instagram.android", 2000).changed) // same app
        assertEquals(false, Hourglass.front(events, "com.whatsapp", 4000).changed) // nothing new
        // Screen off and back on the same app: look again, it may be paused now.
        val again = Hourglass.front(
            sequenceOf(Triple(SCREEN_NON_INTERACTIVE, "android", 5000L), Triple(ACTIVITY_RESUMED, "com.instagram.android", 9000L)),
            "com.instagram.android", 4000,
        )
        assertEquals("com.instagram.android", again.pkg)
        assertEquals(true, again.changed)
    }
}
