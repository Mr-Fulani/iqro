package forum.iqro.app

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * The microphone as 16 kHz mono 16-bit sound, 50 ms at a time, for the trial
 * of the recitation check with a model on the phone
 * (docs/recitation-on-device-spike). Nothing listens to this channel in a
 * build made without `--dart-define=RECITATION_MODEL=true`.
 */
class RecitationMic(private val activity: Activity) : EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var recording = false
    private var thread: Thread? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED) {
            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 4711)
            events.error("permission", "the microphone is not allowed yet", null)
            return
        }
        val rate = 16000
        val chunk = rate / 20
        val record = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION, rate,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                maxOf(AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT), chunk * 8),
            )
        } catch (error: Exception) {
            events.error("microphone", error.message, null)
            return
        }
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            events.error("microphone", "not available", null)
            return
        }
        recording = true
        thread = Thread {
            val samples = ShortArray(chunk)
            record.startRecording()
            while (recording) {
                val read = record.read(samples, 0, chunk)
                if (read <= 0) continue
                val bytes = ByteBuffer.allocate(read * 2).order(ByteOrder.LITTLE_ENDIAN)
                bytes.asShortBuffer().put(samples, 0, read)
                val sound = bytes.array()
                main.post { if (recording) events.success(sound) }
            }
            record.stop()
            record.release()
        }.also { it.start() }
    }

    override fun onCancel(arguments: Any?) {
        recording = false
        thread = null
    }
}
