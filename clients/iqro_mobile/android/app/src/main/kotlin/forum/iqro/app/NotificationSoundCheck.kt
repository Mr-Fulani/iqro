package forum.iqro.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.AudioPlaybackConfiguration
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.RequiresApi

// Android reports muted channels, but firmwares add switches of their own: MIUI's
// per-app "Allow sound" is private to SystemUI and off by default. A notification
// with a silent file still starts the system player when sound is allowed, so
// the player appearing answers what no API does.
@RequiresApi(Build.VERSION_CODES.O)
class NotificationSoundCheck(
    private val context: Context,
    private val done: (Boolean) -> Unit,
) : AudioManager.AudioPlaybackCallback() {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val handler = Handler(Looper.getMainLooper())
    private var polls = 0
    private var finished = false

    // A busy phone takes seconds to accept a notification, so the wait for the
    // player only starts once it has.
    private val awaitPosted = object : Runnable {
        override fun run() {
            when {
                notifications.activeNotifications.any { it.id == NOTIFICATION_ID } ->
                    handler.postDelayed({ finish(false) }, PLAYER_WAIT_MS)
                ++polls < MAX_POLLS -> handler.postDelayed(this, POLL_MS)
                else -> finish(false)
            }
        }
    }

    fun start() {
        if (adhanMuted()) return done(false)
        // Nothing plays on a silent phone, and no app setting would change that.
        if (phoneSilent()) return done(true)
        audio.registerAudioPlaybackCallback(this, handler)
        notifications.createNotificationChannel(channel())
        notifications.notify(
            NOTIFICATION_ID,
            Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.iqro_status_icon)
                .setContentTitle(context.applicationInfo.loadLabel(context.packageManager))
                .build(),
        )
        handler.post(awaitPosted)
    }

    override fun onPlaybackConfigChanged(configs: MutableList<AudioPlaybackConfiguration>) {
        if (configs.any { it.audioAttributes.usage == AudioAttributes.USAGE_NOTIFICATION }) finish(true)
    }

    private fun adhanMuted(): Boolean =
        !notifications.areNotificationsEnabled() || notifications.notificationChannels.any {
            it.id.startsWith(ADHAN_CHANNELS) &&
                (it.importance < NotificationManager.IMPORTANCE_DEFAULT || it.sound == null)
        }

    private fun phoneSilent(): Boolean =
        audio.ringerMode != AudioManager.RINGER_MODE_NORMAL ||
            audio.getStreamVolume(AudioManager.STREAM_NOTIFICATION) == 0 ||
            notifications.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL

    private fun channel(): NotificationChannel {
        val sound = Uri.parse("android.resource://${context.packageName}/raw/sound_check")
        val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build()
        // Like the reminders: MIUI plays nothing below high importance.
        return NotificationChannel(CHANNEL, "Sound check", NotificationManager.IMPORTANCE_HIGH).apply {
            setSound(sound, attributes)
            enableVibration(false)
            setShowBadge(false)
        }
    }

    private fun finish(allowed: Boolean) {
        // The audio callback can arrive twice for one player.
        if (finished) return
        finished = true
        handler.removeCallbacksAndMessages(null)
        audio.unregisterAudioPlaybackCallback(this)
        // Takes the test notification with it and keeps the channel off the settings list.
        notifications.deleteNotificationChannel(CHANNEL)
        done(allowed)
    }

    private companion object {
        const val ADHAN_CHANNELS = "iqro_reminders_adhan_"
        const val CHANNEL = "iqro_sound_probe"
        const val NOTIFICATION_ID = 7714
        const val POLL_MS = 200L
        const val MAX_POLLS = 50
        const val PLAYER_WAIT_MS = 3000L
    }
}
