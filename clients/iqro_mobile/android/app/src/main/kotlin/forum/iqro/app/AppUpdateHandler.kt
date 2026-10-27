package forum.iqro.app

import android.app.Activity
import android.content.IntentSender
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Google Play in-app updates for `play_app_update.dart`. Only the FLEXIBLE flow:
 * the update downloads while the app stays usable, and the user restarts when ready.
 * Builds that Play did not install (debug, adb) fail the check, and Dart treats
 * that as «nothing to offer».
 */
class AppUpdateHandler(
    private val activity: Activity,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val manager: AppUpdateManager by lazy { AppUpdateManagerFactory.create(activity) }
    // Play accepts each AppUpdateInfo for one update flow only.
    private var info: AppUpdateInfo? = null
    private var pendingStart: MethodChannel.Result? = null
    private var sink: EventChannel.EventSink? = null
    private val listener = InstallStateUpdatedListener { state ->
        sink?.success(statusName(state.installStatus()))
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "check" -> check(result)
            "startFlexible" -> startFlexible(result)
            "complete" -> manager.completeUpdate()
                .addOnSuccessListener { result.success(null) }
                .addOnFailureListener { result.error("unavailable", it.message, null) }
            else -> result.notImplemented()
        }
    }

    private fun check(result: MethodChannel.Result) {
        manager.appUpdateInfo
            .addOnSuccessListener { update ->
                info = update
                result.success(
                    mapOf(
                        "available" to (update.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE),
                        "installStatus" to statusName(update.installStatus()),
                        "versionCode" to update.availableVersionCode(),
                        "priority" to update.updatePriority(),
                        "flexibleAllowed" to update.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
                    ),
                )
            }
            .addOnFailureListener { result.error("unavailable", it.message, null) }
    }

    private fun startFlexible(result: MethodChannel.Result) {
        val update = info
        info = null
        if (update == null || !update.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE)) {
            result.success(false)
            return
        }
        pendingStart?.success(false)
        pendingStart = result
        val started = try {
            manager.startUpdateFlowForResult(
                update,
                activity,
                AppUpdateOptions.newBuilder(AppUpdateType.FLEXIBLE).build(),
                REQUEST_CODE,
            )
        } catch (_: IntentSender.SendIntentException) {
            false
        }
        if (!started) {
            pendingStart = null
            result.success(false)
        }
    }

    /** True when Play's update dialog answered; RESULT_OK means the download started. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        pendingStart?.success(resultCode == Activity.RESULT_OK)
        pendingStart = null
        return true
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        manager.registerListener(listener)
    }

    override fun onCancel(arguments: Any?) {
        if (sink == null) return
        manager.unregisterListener(listener)
        sink = null
    }

    private fun statusName(status: Int): String = when (status) {
        InstallStatus.PENDING -> "pending"
        InstallStatus.DOWNLOADING -> "downloading"
        InstallStatus.DOWNLOADED -> "downloaded"
        InstallStatus.INSTALLING -> "installing"
        InstallStatus.INSTALLED -> "installed"
        InstallStatus.FAILED -> "failed"
        InstallStatus.CANCELED -> "canceled"
        else -> "unknown"
    }

    private companion object {
        const val REQUEST_CODE = 0x1A0D
    }
}
