package com.eylexander.sablier

import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.widget.Toast

// Watches which app comes to the front, from the usage events read every second while the screen is on (no
// accessibility service: with one on, apps like Instagram run slower). When one of a rule's apps is open, it checks
// the rule again when the time left runs out, warns a minute before, and covers the app with the pause screen
// (MainActivity, allowed from the background by the "display over other apps" permission) once the budget is spent.
// Hush runs it: the system keeps a notification listener running, like it did the accessibility service.
class Guard(private val hush: Hush) {
    private val handler = Handler(Looper.getMainLooper())
    private val check = Runnable { check() }
    private val poll = object : Runnable {
        override fun run() {
            poll()
            handler.postDelayed(this, 1000)
        }
    }
    private val power = hush.getSystemService(PowerManager::class.java)
    private var front: String? = null
    private var seen = 0L // time of the last usage event handled
    private var polled = 0L
    private val warned = mutableSetOf<String>()

    fun start() = handler.post(poll)

    fun stop() = handler.removeCallbacksAndMessages(null)

    private fun poll() {
        if (!power.isInteractive) return
        val now = System.currentTimeMillis()
        // A few seconds back: the usage stats record an event a moment after its time. At most an hour on start.
        val from = if (polled == 0L) now - 3_600_000 else polled - 5000
        polled = now
        val f = Hourglass.front(Rules.events(hush, from, now), front, seen)
        seen = f.seen
        if (f.changed) show(f.pkg)
    }

    private fun show(pkg: String?) {
        front = pkg
        handler.removeCallbacks(check)
        if (pkg == null) return
        // Already paused: cover it at once, the usage stats aren't needed for that.
        Rules.paused(hush, pkg, System.currentTimeMillis()).firstOrNull()?.let { return pause(it.first) }
        check()
    }

    private fun check() {
        handler.removeCallbacks(check)
        val now = System.currentTimeMillis()
        var next = Long.MAX_VALUE
        for (rule in Rules.load(hush)) {
            if (!rule.on) continue
            val s = Rules.status(hush, rule, now)
            if (!s.open) continue
            if (s.blocked) return pause(rule)
            if (s.left > 60_000) {
                warned.remove(rule.id)
                next = minOf(next, s.left - 60_000)
            } else {
                if (warned.add(rule.id)) Toast.makeText(hush, "${rule.name} : plus qu'une minute", Toast.LENGTH_LONG).show()
                next = minOf(next, s.left)
            }
        }
        // Screen off or app closed in between: the next check sees it and waits for the next app change.
        if (next != Long.MAX_VALUE) handler.postDelayed(check, maxOf(next, 1000))
    }

    private fun pause(rule: Rule) {
        hush.hushAll()
        hush.startActivity(
            Intent(hush, MainActivity::class.java)
                .putExtra(MainActivity.PAUSED, rule.id)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }
}
