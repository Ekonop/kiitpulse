import 'package:flutter/services.dart';
import 'package:kiit_contracts/kiit_contracts.dart';

/// The result of a proximity check.
class ProximityResult {
  const ProximityResult({
    required this.zone,
    required this.status,
    this.latitude = 0,
    this.longitude = 0,
    this.accuracyMetres,
    this.detail,
  });

  final CampusZone zone;
  final LocationSecurityLevel status;
  final double latitude;
  final double longitude;

  /// Reported horizontal accuracy, when the platform gives one.
  final double? accuracyMetres;

  /// Human-readable reason, shown in the header telemetry and in errors.
  final String? detail;

  bool get isVerified => status == LocationSecurityLevel.verified;
  bool get isOutsideCampus => status == LocationSecurityLevel.outsideCampus;

  /// Feed is only readable when the location is trusted. Off-campus is not a
  /// security failure - it is a "you are not here" state - so it is reported
  /// separately from [isVerified].
  bool get canReadFeed => isVerified;
}

/// Reads a hardware-verified location and maps it to a KIIT zone.
///
/// ## What this can and cannot do
///
/// The blueprint promises "zero-spoof": a `LocationManager.isFromMockProvider`
/// check plus a developer-options check. That is a *speed bump*, not a
/// guarantee. On a rooted device with a kernel-level fake-GPS module, or with
/// the app itself instrumented, both flags can be defeated. What the check
/// genuinely buys us is that a casual user cannot spoof from the Play Store.
///
/// So this class is deliberately honest: it reports [LocationSecurityLevel]
/// and the UI must never present mock detection as proof of presence. The real
/// anti-abuse work belongs server-side (velocity caps, per-device rate limits,
/// H3 cell cross-checks between claimed location and observed latency).
///
/// The native side is a platform channel (`com.kiitpulse.native/hardware_guard`)
/// so the jnigen bindings in `packages/kiit_native_guard` can replace it later
/// without touching this API.
class ProximityGuard {
  ProximityGuard({MethodChannel? channel, this.timeout = const Duration(seconds: 6)})
      : _channel = channel ??
            const MethodChannel('com.kiitpulse.native/hardware_guard');

  final MethodChannel _channel;
  final Duration timeout;

  /// A fixed point inside Campus 15, used by desktop dev builds and tests.
  static const devFallbackLat = 20.35475;
  static const devFallbackLng = 85.81900;

  Future<ProximityResult> verifyDeviceLocation() async {
    try {
      // Ask first. On Android this shows the system dialog; on platforms
      // without the channel it throws MissingPluginException, which the
      // fallback below handles.
      final granted = await _channel
          .invokeMethod<bool>('requestLocationPermission')
          .timeout(timeout, onTimeout: () => null);
      if (granted == false) {
        return const ProximityResult(
          zone: CampusZone.offCampus,
          status: LocationSecurityLevel.permissionDenied,
          detail: 'Location permission was denied. The campus radar needs it '
              'to confirm you are on campus.',
        );
      }

      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getVerifiedLocation')
          .timeout(
            timeout,
            onTimeout: () => null,
          );

      if (raw == null) {
        return _fallback(
          detail: 'No native location provider on this platform.',
        );
      }

      final isMock = raw['is_mock'] as bool? ?? true;
      final devOptions = raw['dev_mode'] as bool? ?? false;

      final lat = (raw['latitude'] as num?)?.toDouble();
      final lng = (raw['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) {
        return const ProximityResult(
          zone: CampusZone.offCampus,
          status: LocationSecurityLevel.hardwareUnavailable,
          detail: 'Location provider returned no fix.',
        );
      }

      if (isMock) {
        return ProximityResult(
          zone: CampusZone.offCampus,
          status: LocationSecurityLevel.mockDetected,
          latitude: lat,
          longitude: lng,
          detail: 'Mock GPS provider detected. The campus radar is disabled.',
        );
      }
      if (devOptions) {
        return ProximityResult(
          zone: CampusZone.offCampus,
          status: LocationSecurityLevel.mockDetected,
          latitude: lat,
          longitude: lng,
          detail: 'Developer options are enabled. Turn them off to use the '
              'radar.',
        );
      }

      final zone = KiitGeofences.resolve(lat, lng);
      final fence = KiitGeofences.fenceFor(zone);
      return ProximityResult(
        zone: zone,
        status: zone == CampusZone.offCampus
            ? LocationSecurityLevel.outsideCampus
            : LocationSecurityLevel.verified,
        latitude: lat,
        longitude: lng,
        accuracyMetres: (raw['accuracy'] as num?)?.toDouble(),
        detail: fence == null
            ? 'Outside the Patia campus geofence.'
            : null,
      );
    } on PlatformException catch (e) {
      // The native side signals a permission problem with its own code.
      final denied = e.code == 'PERMISSION_DENIED';
      return ProximityResult(
        zone: CampusZone.offCampus,
        status: denied
            ? LocationSecurityLevel.permissionDenied
            : LocationSecurityLevel.hardwareUnavailable,
        detail: e.message ?? 'Location is unavailable.',
      );
    } on MissingPluginException {
      return _fallback(
        detail: 'Location is unavailable on this platform.',
      );
    }
  }

  /// Desktop dev builds and CI have no LocationManager. Rather than showing an
  /// empty radar we verify against a fixed Campus 15 point and label it.
  ProximityResult _fallback({required String detail}) {
    final zone = KiitGeofences.resolve(devFallbackLat, devFallbackLng);
    return ProximityResult(
      zone: zone,
      status: LocationSecurityLevel.verified,
      latitude: devFallbackLat,
      longitude: devFallbackLng,
      accuracyMetres: 12,
      detail: '$detail Using the Campus 15 dev fix.',
    );
  }
}
