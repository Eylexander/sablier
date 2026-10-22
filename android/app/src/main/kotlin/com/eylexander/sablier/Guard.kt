package com.eylexander.sablier

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast

// Watches which app comes to the front (window changes only: it never reads what's on screen). When one of a
// rule's apps is open, it checks the rule again when the time left runs out, warns a minute before, and covers
// the app with the pause screen (MainActivity) once the budget is spent.
class Guard : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private val check = Runnable { check() }
    private var last: String? = null
    private val warned = mutableSetOf<String>()

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return
        if (pkg == last) return
        last = pkg
        handler.removeCallbacks(check)
        handler.postDelayed(check, 300) // let the usage stats record the new activity first
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        handler.removeCallbacks(check)
        super.onDestroy()
    }

    private fun check() {
        handler.removeCallbacks(check)
        val now = System.currentTimeMillis()
        var next = Long.MAX_VALUE
        for (rule in Rules.load(this)) {
            if (!rule.on) continue
            val s = Rules.status(this, rule, now)
            if (!s.open) continue
            if (s.blocked) return pause(rule)
            if (s.left > 60_000) {
                warned.remove(rule.id)
                next = minOf(next, s.left - 60_000)
            } else {
                if (warned.add(rule.id)) Toast.makeText(this, "${rule.name} : plus qu'une minute", Toast.LENGTH_LONG).show()
                next = minOf(next, s.left)
            }
        }
        // Screen off or app closed in between: the next check sees it and waits for the next window change.
        if (next != Long.MAX_VALUE) handler.postDelayed(check, maxOf(next, 1000))
    }

    private fun pause(rule: Rule) = startActivity(
        Intent(this, MainActivity::class.java)
            .putExtra(MainActivity.PAUSED, rule.id)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
    )
}
