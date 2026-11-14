package com.kiitpulse.kiitpulse

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the app and answers the proximity channel.
 *
 * The channel contract is read-only: Dart asks "where is this device and can I
 * trust that answer", and gets a map. No navigation, no writes, nothing the
 * client could abuse to move its own reported position.
 *
 * Honest note on mock detection: `Location.isFromMockProvider` is deprecated
 * from API 31 and can be defeated on a rooted device. It raises the cost of
 * casual spoofing and it is worth having, but it is not a guarantee, and the
 * Flutter side is written to say only what it can actually verify.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.kiitpulse.native/hardware_guard"
        const val REQ_LOCATION = 4401
    }

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getVerifiedLocation" -> handleGetVerifiedLocation(result)
                    "requestLocationPermission" -> requestLocationPermission(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasLocationPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    private fun requestLocationPermission(result: MethodChannel.Result) {
        if (hasLocationPermission()) {
            result.success(true)
            return
        }
        pendingResult = result
        requestPermissions(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ),
            REQ_LOCATION
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_LOCATION) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingResult?.success(granted)
        pendingResult = null
    }

    private fun handleGetVerifiedLocation(result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            // Report the denial as a code rather than throwing: the Dart side
            // maps it to LocationSecurityLevel.permissionDenied.
            result.error("PERMISSION_DENIED", "Location permission not granted", null)
            return
        }

        val manager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (manager == null) {
            result.error("HARDWARE_UNAVAILABLE", "No LocationManager on this device", null)
            return
        }

        val location: Location? = try {
            lastKnown(manager)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message, null)
            return
        } catch (e: Exception) {
            result.error("HARDWARE_UNAVAILABLE", e.message, null)
            return
        }

        if (location == null) {
            result.success(null)
            return
        }

        val mock = isMock(location)
        val devOptions = isDeveloperOptionsEnabled()

        result.success(
            mapOf(
                "latitude" to location.latitude,
                "longitude" to location.longitude,
                "accuracy" to if (location.hasAccuracy()) location.accuracy.toDouble() else null,
                "is_mock" to mock,
                "dev_mode" to devOptions,
                "provider" to location.provider,
                "timestamp" to location.time
            )
        )
    }

    /** Best fix available, preferring GPS accuracy over network. */
    private fun lastKnown(manager: LocationManager): Location? {
        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER
        )
        var best: Location? = null
        for (provider in providers) {
            if (!manager.isProviderEnabled(provider)) continue
            val candidate = try {
                manager.getLastKnownLocation(provider)
            } catch (e: Exception) {
                null
            } ?: continue
            if (best == null || candidate.accuracy < best.accuracy) best = candidate
        }
        return best
    }

    private fun isMock(location: Location): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            location.isMock
        } else {
            @Suppress("DEPRECATION")
            location.isFromMockProvider
        }
    }

    private fun isDeveloperOptionsEnabled(): Boolean {
        return try {
            Settings.Global.getInt(
                contentResolver,
                Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0
            ) != 0
        } catch (e: Exception) {
            false
        }
    }
}
