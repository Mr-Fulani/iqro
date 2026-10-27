package forum.iqro.app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import io.flutter.plugin.common.EventChannel

/**
 * Device orientation for the Qibla compass (`qibla_compass.dart`). Dart turns the
 * rotation matrix into a heading for the current display rotation and adds the WMM
 * magnetic declination. Sensors are registered only while Dart listens, so they stop
 * when the Qibla sheet closes or the app leaves the foreground. No permission needed.
 */
class QiblaCompassStreamHandler(
    context: Context,
    private val displayRotation: () -> Int,
) : EventChannel.StreamHandler, SensorEventListener {
    private val sensors = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager?
    private val matrix = FloatArray(9)
    private var sink: EventChannel.EventSink? = null
    private var fused = false
    private var gravity: FloatArray? = null
    private var magneticStatus = -1
    private var lastEmit = 0L

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val magnetometer = sensors?.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
        // Gyroscope-fused orientation where available; otherwise accelerometer + magnetometer.
        val orientation = sensors?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            ?: sensors?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (sensors == null || magnetometer == null || orientation == null) {
            events.error("unavailable", "No compass sensor", null)
            return
        }
        sink = events
        fused = orientation.type == Sensor.TYPE_ROTATION_VECTOR
        // Also the source of the calibration status in the fused mode. Some
        // tablets list sensors they cannot open; say so instead of a still dial.
        if (!sensors.registerListener(this, orientation, SAMPLING_PERIOD_US) ||
            !sensors.registerListener(this, magnetometer, SAMPLING_PERIOD_US)
        ) {
            onCancel(null)
            events.error("unavailable", "Compass sensor did not start", null)
        }
    }

    override fun onCancel(arguments: Any?) {
        sensors?.unregisterListener(this)
        sink = null
        gravity = null
        magneticStatus = -1
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {
        if (sensor.type == Sensor.TYPE_MAGNETIC_FIELD) magneticStatus = accuracy
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR -> {
                // Some Samsung devices reject vectors longer than four values.
                val vector = if (event.values.size > 4) event.values.copyOf(4) else event.values
                SensorManager.getRotationMatrixFromVector(matrix, vector)
                emit()
            }
            Sensor.TYPE_ACCELEROMETER -> gravity = event.values.copyOf(3)
            Sensor.TYPE_MAGNETIC_FIELD -> {
                magneticStatus = event.accuracy
                val gravity = gravity
                if (!fused && gravity != null &&
                    SensorManager.getRotationMatrix(matrix, null, gravity, event.values)
                ) {
                    emit()
                }
            }
        }
    }

    private fun emit() {
        val events = sink ?: return
        val now = SystemClock.elapsedRealtime()
        if (now - lastEmit < MIN_EMIT_INTERVAL_MS) return
        lastEmit = now
        events.success(
            mapOf(
                "matrix" to matrix.map { it.toDouble() },
                "rotation" to displayRotation(),
                "status" to magneticStatus,
            ),
        )
    }

    private companion object {
        const val SAMPLING_PERIOD_US = 33_000
        const val MIN_EMIT_INTERVAL_MS = 30L
    }
}
