package com.eylexander.sablier

import android.app.AppOpsManager
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Process
import android.provider.AlarmClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

// The Flutter side's window on Android (channel "sablier/guard", see lib/guard.dart): rules, their status,
// installed apps and permissions. Guard opens this activity with PAUSED to show the pause screen.
class MainActivity : FlutterActivity() {
    companion object {
        const val PAUSED = "paused"
    }

    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sablier/guard").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "rules" -> result.success(Rules.prefs(this@MainActivity).getString("rules", null))
                    "setRules" -> {
                        Rules.prefs(this@MainActivity).edit().putString("rules", call.arguments as String).apply()
                        result.success(null)
                    }
                    "status" -> result.success(status())
                    "apps" -> result.success(apps())
                    "icon" -> result.success(icon(call.arguments as String))
                    "access" -> result.success(
                        mapOf("usage" to usageAccess(), "guard" to guardOn(), "notifications" to notificationsOn()),
                    )
                    "openUsage" -> settings(Settings.ACTION_USAGE_ACCESS_SETTINGS, result)
                    "openGuard" -> settings(Settings.ACTION_ACCESSIBILITY_SETTINGS, result)
                    "openNotifications" -> settings(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS, result)
                    "openAppInfo" -> settings(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, result, Uri.parse("package:$packageName"))
                    "takePaused" -> {
                        result.success(intent.getStringExtra(PAUSED))
                        intent.removeExtra(PAUSED)
                    }
                    "open" -> result.success(open(call.arguments as String))
                    "home" -> {
                        startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra(PAUSED)?.let { channel?.invokeMethod("paused", it) }
    }

    private fun status(): List<Map<String, Any>> {
        val now = System.currentTimeMillis()
        return Rules.load(this).map { rule ->
            val s = Rules.status(this, rule, now)
            mapOf(
                "id" to rule.id, "now" to now, "used" to s.used, "left" to s.left, "until" to s.until,
                "sessions" to s.sessions.flatMap { listOf(it.start, it.end) },
            )
        }
    }

    /** Launchable apps as [package, label] pairs, by label. */
    private fun apps(): List<List<String>> {
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return packageManager.queryIntentActivities(launcher, 0)
            .map { listOf(it.activityInfo.packageName, it.loadLabel(packageManager).toString()) }
            .filter { it[0] != packageName }
            .distinctBy { it[0] }
            .sortedBy { it[1].lowercase() }
    }

    private fun icon(pkg: String): ByteArray? = try {
        val d = packageManager.getApplicationIcon(pkg)
        val b = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
        d.setBounds(0, 0, 96, 96)
        d.draw(Canvas(b))
        ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    } catch (e: Exception) {
        null
    }

    private fun usageAccess() = getSystemService(AppOpsManager::class.java)
        .unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName) == AppOpsManager.MODE_ALLOWED

    private fun guardOn() = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        ?.contains("$packageName/") == true

    private fun notificationsOn() = getSystemService(NotificationManager::class.java)
        .isNotificationListenerAccessGranted(ComponentName(this, Hush::class.java))

    /** Starts what a pause screen suggestion offers: "dial", "music" or "timer:<seconds>". False if no app can. */
    private fun open(what: String): Boolean {
        val intent = when {
            what == "dial" -> Intent(Intent.ACTION_DIAL)
            what == "music" -> Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_MUSIC)
            what.startsWith("timer:") -> Intent(AlarmClock.ACTION_SET_TIMER)
                .putExtra(AlarmClock.EXTRA_LENGTH, what.removePrefix("timer:").toInt())
                .putExtra(AlarmClock.EXTRA_SKIP_UI, false)
            else -> return false
        }
        return try {
            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    private fun settings(action: String, result: MethodChannel.Result, data: Uri? = null) {
        startActivity(Intent(action).setData(data))
        result.success(null)
    }
}
