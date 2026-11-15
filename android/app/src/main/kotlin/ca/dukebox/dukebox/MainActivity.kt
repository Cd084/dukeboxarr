package ca.dukebox.dukebox

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.PowerManager
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity (audio_service) shares the Flutter engine with the
// background media service, so playback continues while the screen is locked.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ca.dukebox/power")
            .setMethodCallHandler { call, result ->
                val ctx = applicationContext
                when (call.method) {
                    "hold" -> {
                        PlaybackLocks.hold(ctx, call.arguments as Boolean)
                        result.success(null)
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(ctx.packageName))
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:${ctx.packageName}"),
                            )
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

/**
 * While music is playing: a partial wake lock keeps the CPU running and a
 * Wi-Fi lock keeps Wi-Fi at full power with the screen off. Without them a
 * real tablet lets Wi-Fi doze once the screen turns off, the stream from Plex
 * drops and playback stops (the emulator never sleeps, so it hides this).
 * Same approach as ExoPlayer-based players (Plexamp, Spotify, ...).
 */
object PlaybackLocks {
    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null

    @SuppressLint("WakelockTimeout")
    @Suppress("DEPRECATION") // HIGH_PERF is what keeps Wi-Fi up with the screen off
    @Synchronized
    fun hold(ctx: Context, on: Boolean) {
        if (on) {
            if (wake == null) {
                val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
                wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DukeBoxarr:playback").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
            if (wifi == null) {
                val wm = ctx.getSystemService(Context.WIFI_SERVICE) as WifiManager
                wifi = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "DukeBoxarr:playback").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        } else {
            wake?.let { if (it.isHeld) it.release() }
            wifi?.let { if (it.isHeld) it.release() }
            wake = null
            wifi = null
        }
    }
}
