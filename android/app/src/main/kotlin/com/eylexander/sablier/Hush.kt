package com.eylexander.sablier

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

// Snoozes the notifications of a paused rule's apps until the pause ends, when Android posts them again: tapping one
// would open the app (and mark a message read) before Guard can cover it. It only looks at the package, never the
// content.
class Hush : NotificationListenerService() {
    companion object {
        var instance: Hush? = null
    }

    override fun onListenerConnected() {
        instance = this
        hushAll()
    }

    override fun onListenerDisconnected() {
        instance = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) = hush(sbn, System.currentTimeMillis())

    /** The notifications already there when a pause starts (Guard calls it). */
    fun hushAll() {
        val now = System.currentTimeMillis()
        activeNotifications?.forEach { hush(it, now) }
    }

    private fun hush(sbn: StatusBarNotification, now: Long) {
        val until = Rules.paused(this, sbn.packageName, now).maxOfOrNull { it.second } ?: return
        snoozeNotification(sbn.key, until - now)
    }
}
