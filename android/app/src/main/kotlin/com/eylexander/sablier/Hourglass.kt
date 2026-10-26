package com.eylexander.sablier

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import org.json.JSONArray

/** A rule: its apps may be on screen [budget] ms in any [window] ms (a sliding window, like sand coming back). */
data class Rule(val id: String, val name: String, val apps: Set<String>, val budget: Long, val window: Long, val on: Boolean)

/** A stretch of time one of a rule's apps was on screen, in epoch ms. */
data class Session(val start: Long, val end: Long)

/** The app in front ([pkg], null while the screen is off) after the usage events up to [seen]. */
class Front(val pkg: String?, val seen: Long, val changed: Boolean)

class Status(val used: Long, val left: Long, val open: Boolean, val until: Long, val sessions: List<Session>) {
    val blocked get() = until > 0
}

/** The window arithmetic, without Android (UsageTest covers it). */
object Hourglass {
    /** Time on screen within [from, to]. */
    fun used(sessions: List<Session>, from: Long, to: Long) =
        sessions.sumOf { maxOf(0L, minOf(it.end, to) - maxOf(it.start, from)) }

    /** First moment from [now] when [need] ms of the budget are free again, if the apps stay closed. */
    fun freeAt(sessions: List<Session>, budget: Long, window: Long, need: Long, now: Long): Long {
        fun ok(t: Long) = budget - used(sessions, t - window, t) >= need
        if (ok(now)) return now
        var lo = now
        var hi = now + window // the whole window has slid past every session
        while (hi - lo > 1000) {
            val mid = (lo + hi) / 2
            if (ok(mid)) hi = mid else lo = mid
        }
        return hi
    }

    /**
     * Turns usage events (type, package, time; in time order) into sessions of [apps] within [from, now].
     * An app already on screen at [from] shows up as a pause without a resume.
     */
    fun sessions(events: Sequence<Triple<Int, String, Long>>, apps: Set<String>, from: Long, now: Long): List<Session> {
        val out = mutableListOf<Session>()
        var start: Long? = null
        var seen = false
        fun close(t: Long) {
            start?.let { out += Session(it, t) }
            start = null
        }
        for ((type, pkg, t) in events) {
            when (type) {
                UsageEvents.Event.ACTIVITY_RESUMED -> if (pkg in apps) { if (start == null) start = t } else close(t)
                UsageEvents.Event.ACTIVITY_PAUSED -> if (pkg in apps) {
                    if (start == null && !seen) start = from
                    close(t)
                }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> close(t)
                else -> continue
            }
            seen = true
        }
        close(now)
        return out
    }

    /**
     * Follows the app in front through the usage events (type, package, time; in time order) newer than [seen], from
     * [front]. Changed if another app came to the front, or the screen went off (the app may need covering again).
     */
    fun front(events: Sequence<Triple<Int, String, Long>>, front: String?, seen: Long): Front {
        var pkg = front
        var last = seen
        var changed = false
        for ((type, p, t) in events) {
            if (t <= last) continue // already handled (polls overlap)
            last = t
            when (type) {
                UsageEvents.Event.ACTIVITY_RESUMED -> if (p != pkg) { pkg = p; changed = true }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> { pkg = null; changed = true }
            }
        }
        return Front(pkg, last, changed)
    }
}

/** Rules (written by the Flutter side as JSON) and their live status from Android's usage stats. */
object Rules {
    fun prefs(c: Context) = c.getSharedPreferences("sablier", Context.MODE_PRIVATE)

    fun load(c: Context): List<Rule> {
        val json = JSONArray(prefs(c).getString("rules", null) ?: return emptyList())
        return (0 until json.length()).map { i ->
            val r = json.getJSONObject(i)
            val apps = r.getJSONArray("apps")
            Rule(
                r.getString("id"), r.getString("name"), (0 until apps.length()).map(apps::getString).toSet(),
                r.getLong("budget") * 60_000, r.getLong("window") * 60_000, r.getBoolean("on"),
            )
        }
    }

    fun status(c: Context, rule: Rule, now: Long): Status {
        val from = now - rule.window
        val sessions = Hourglass.sessions(events(c, from, now), rule.apps, from, now)
        val used = Hourglass.used(sessions, from, now)
        val key = "until.${rule.id}"
        var until = prefs(c).getLong(key, 0)
        if (until <= now) {
            // Once the budget is spent, the pause lasts until a full minute is back (not a few seconds at a time).
            until = if (used >= rule.budget) Hourglass.freeAt(sessions, rule.budget, rule.window, minOf(60_000L, rule.budget), now) else 0
            prefs(c).edit().putLong(key, until).apply()
        }
        val open = sessions.lastOrNull()?.end == now
        return Status(used, if (until > 0) 0 else maxOf(0, rule.budget - used), open, until, sessions)
    }

    /** The rules holding [pkg] that are paused at [now], with the end of their pause (as [status] stored it). */
    fun paused(c: Context, pkg: String, now: Long) = load(c).filter { it.on && pkg in it.apps }
        .map { it to prefs(c).getLong("until.${it.id}", 0) }
        .filter { it.second > now }

    fun events(c: Context, from: Long, now: Long) = sequence {
        val events = c.getSystemService(UsageStatsManager::class.java).queryEvents(from, now)
        val e = UsageEvents.Event()
        while (events.getNextEvent(e)) yield(Triple(e.eventType, e.packageName, e.timeStamp))
    }
}
