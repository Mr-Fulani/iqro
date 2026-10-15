package forum.iqro.app

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.media.AudioAttributes
import android.os.Build
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var lastPagePulse = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        refreshNotificationIcons()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "forum.iqro.app/reader_haptics")
            .setMethodCallHandler { call, result ->
                if (call.method != "pageTick") {
                    result.notImplemented()
                } else {
                    try {
                        result.success(pageTick())
                    } catch (_: SecurityException) {
                        result.success("unavailable")
                    }
                }
            }
    }

    private fun refreshNotificationIcons() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // Already posted notifications survive APK updates. Preserve their text,
        // actions and pending intents while replacing the previous branding.
        for (active in manager.activeNotifications) {
            val notification = active.notification
            val reminder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                notification.channelId?.startsWith("iqro_reminders_") == true
            } else {
                notification.category == Notification.CATEGORY_REMINDER
            }
            val audio = notification.category == Notification.CATEGORY_TRANSPORT
            if (!reminder && !audio) continue
            @Suppress("DEPRECATION")
            val previousAppInfo = notification.extras.getParcelable<ApplicationInfo>("android.appInfo")
            if (notification.smallIcon?.resId == R.drawable.iqro_status_icon &&
                previousAppInfo?.icon == applicationInfo.icon &&
                (!reminder || notification.getLargeIcon() == null)) continue
            val builder = Notification.Builder.recoverBuilder(this, notification)
                .setSmallIcon(R.drawable.iqro_status_icon)
                .setOnlyAlertOnce(true)
            if (reminder) builder.setLargeIcon(null as Bitmap?)
            try {
                manager.notify(active.tag, active.id, builder.build())
            } catch (_: SecurityException) {
                // Notification permission may have been revoked in Settings.
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun pageTick(): String {
        if (Settings.System.getInt(contentResolver, Settings.System.HAPTIC_FEEDBACK_ENABLED, 1) == 0) {
            return "disabled"
        }
        val motor = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            ?: return "unavailable"
        if (!motor.hasVibrator()) return "unavailable"
        val now = SystemClock.uptimeMillis()
        if (now - lastPagePulse < 70) return "throttled"
        lastPagePulse = now
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // CLOCK_TICK can be ineffective on MIUI. This short pulse does not
            // depend on OEM predefined-effect support or ignore system settings.
            val amplitude = if (motor.hasAmplitudeControl()) 110 else VibrationEffect.DEFAULT_AMPLITUDE
            motor.vibrate(VibrationEffect.createOneShot(22, amplitude), attributes)
        } else {
            motor.vibrate(22, attributes)
        }
        return "played"
    }
}
