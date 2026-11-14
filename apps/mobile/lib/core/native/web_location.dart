import 'package:kiit_contracts/kiit_contracts.dart';

import 'proximity_guard.dart';
import 'web_location_stub.dart'
    if (dart.library.js_interop) 'web_location_web.dart';

/// Reads location on platforms with no `LocationManager`.
///
/// This exists so the browser build is honest. Flutter's method channel does
/// not exist on web, so the old code fell into its "dev fallback": a fixed
/// Campus 15 coordinate, reported as `verified`. On a phone that was a
/// harmless dev convenience. In a browser it means every web visitor is told
/// they are on campus when they are not, which is precisely the kind of lie
/// this project refuses elsewhere.
///
/// So on web we ask the real browser API. The browser's own honesty is also
/// limited - `GeolocationPosition` has no mock-provider flag at all, so a
/// laptop with a spoofed location is undetectable. That is reported as
/// [LocationSecurityLevel.verified] only because the coordinates are genuine
/// to the browser; the README says plainly that web presence is weaker than
/// Android's.
class WebProximityGuard {
  const WebProximityGuard();

  /// Ask the browser for a fix and map it to a KIIT zone.
  Future<ProximityResult> verifyDeviceLocation() async {
    if (!kWebGeolocationAvailable) {
      return const ProximityResult(
        zone: CampusZone.offCampus,
        status: LocationSecurityLevel.hardwareUnavailable,
        detail: 'This browser cannot report a location. The campus radar '
            'needs it to confirm you are on campus.',
      );
    }

    final fix = await requestWebLocation();
    if (fix == null) {
      return const ProximityResult(
        zone: CampusZone.offCampus,
        status: LocationSecurityLevel.permissionDenied,
        detail: 'Location permission was denied or the browser could not get '
            'a fix. Allow location for this site to use the campus radar.',
      );
    }

    // A browser fix is often wildly inaccurate - a VPN or a desktop with no
    // GPS can resolve to another city. Refusing a fix we know is too coarse is
    // better than confidently placing a student in the wrong hostel.
    if (fix.accuracyMetres > kWorstUsefulAccuracyMetres) {
      return ProximityResult(
        zone: CampusZone.offCampus,
        status: LocationSecurityLevel.hardwareUnavailable,
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracyMetres: fix.accuracyMetres,
        detail: 'This device reported a location accurate only to '
            '${fix.accuracyMetres.round()} m, which is too coarse to tell '
            'which part of campus you are on.',
      );
    }

    final zone = KiitGeofences.resolve(fix.latitude, fix.longitude);
    return ProximityResult(
      zone: zone,
      status: zone == CampusZone.offCampus
          ? LocationSecurityLevel.outsideCampus
          : LocationSecurityLevel.verified,
      latitude: fix.latitude,
      longitude: fix.longitude,
      accuracyMetres: fix.accuracyMetres,
      detail: zone == CampusZone.offCampus
          ? 'Outside the Patia campus geofence.'
          : null,
    );
  }
}

/// A coarse fix is worse than no fix when the question is "which zone".
///
/// The campus geofences are a few hundred metres across, so an accuracy worse
/// than half a zone cannot distinguish them. 250 m leaves room for the slop
/// inside one box without letting a city-level fix pretend to be a campus one.
const double kWorstUsefulAccuracyMetres = 250;

/// The browser's geolocation result, reduced to what the guard needs.
class WebLocationFix {
  const WebLocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMetres,
  });

  final double latitude;
  final double longitude;
  final double accuracyMetres;
}
