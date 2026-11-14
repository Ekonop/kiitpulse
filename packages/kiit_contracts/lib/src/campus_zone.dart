import 'dart:math' as math;

/// The physical KIIT campus zones. Order matters: it is the enum wire order in
/// `contracts/proto/kiitpulse/v1/kiitpulse.proto`.
enum CampusZone {
  unspecified(0, 'CAMPUS_ZONE_UNSPECIFIED', 'Unspecified', ''),
  campus15(1, 'CAMPUS_ZONE_CAMPUS_15', 'Campus 15', 'School of Computer Engg'),
  ksac(2, 'CAMPUS_ZONE_KSAC', 'KSAC', 'Activity Centre'),
  kpHostels(3, 'CAMPUS_ZONE_KP_HOSTELS', 'KP / QC Hostels', 'Residential'),
  foodCourt(4, 'CAMPUS_ZONE_FOOD_COURT', 'Food Court', 'Camellia / Magneto'),
  campus6and7(5, 'CAMPUS_ZONE_CAMPUS_6_AND_7', 'Campus 6 & 7', 'Auditorium'),
  kims(6, 'CAMPUS_ZONE_KIMS', 'KIMS', 'Medical Sciences'),
  offCampus(7, 'CAMPUS_ZONE_OFF_CAMPUS', 'Patia Corridor', 'Outside geofence');

  const CampusZone(this.wire, this.wireName, this.label, this.subtitle);

  /// Numeric value used by the protobuf enum.
  final int wire;

  /// Stable string key used in Redis (`kiit:radar:<zone>`) and Postgres.
  final String wireName;

  /// Short human label for the pill control.
  final String label;

  /// Qualifier shown under the label in headers.
  final String subtitle;

  /// Zones a student can actually be standing in. `unspecified` and
  /// `offCampus` are states, not places.
  static const List<CampusZone> physical = [
    campus15,
    ksac,
    kpHostels,
    foodCourt,
    campus6and7,
    kims,
  ];

  bool get isPhysical => physical.contains(this);

  /// Redis/PG key segment: `campus15`, `kp_hostels`, ...
  String get key {
    switch (this) {
      case CampusZone.campus15:
        return 'campus15';
      case CampusZone.ksac:
        return 'ksac';
      case CampusZone.kpHostels:
        return 'kp_hostels';
      case CampusZone.foodCourt:
        return 'food_court';
      case CampusZone.campus6and7:
        return 'campus6_7';
      case CampusZone.kims:
        return 'kims';
      case CampusZone.offCampus:
        return 'off_campus';
      case CampusZone.unspecified:
        return 'unspecified';
    }
  }

  static CampusZone fromWire(int? value) => CampusZone.values.firstWhere(
        (z) => z.wire == value,
        orElse: () => CampusZone.unspecified,
      );

  static CampusZone fromKey(String? key) => CampusZone.values.firstWhere(
        (z) => z.key == key || z.wireName == key,
        orElse: () => CampusZone.offCampus,
      );
}

/// Why the location is (or is not) trusted.
enum LocationSecurityLevel {
  verified,
  mockDetected,
  permissionDenied,
  hardwareUnavailable,
  outsideCampus,
}

/// Axis-aligned geofence for a zone, in WGS84.
///
/// The blueprint ships bounding boxes rather than polygons. They are good
/// enough for a campus corridor and cheap to test, so we keep them - but the
/// seam is here: swap [contains] for a PostGIS/H3 lookup and nothing else moves.
class ZoneGeofence {
  const ZoneGeofence({
    required this.zone,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  final CampusZone zone;
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  bool contains(double lat, double lng) =>
      lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;

  /// Distance from the fence centre to (lat,lng) in metres, used to show a
  /// precision radius. Flat-earth approximation: fine inside a campus.
  double metresFrom(double lat, double lng) {
    const mPerDegLat = 110574.0;
    final centreLat = (minLat + maxLat) / 2;
    final centreLng = (minLng + maxLng) / 2;
    final mPerDegLng = 111320.0 * math.cos(centreLat * math.pi / 180);
    final dy = (lat - centreLat) * mPerDegLat;
    final dx = (lng - centreLng) * mPerDegLng;
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// The KIIT Patia geofences, in the same order the resolver checks them.
abstract final class KiitGeofences {
  static const List<ZoneGeofence> all = [
    ZoneGeofence(
      zone: CampusZone.campus15,
      minLat: 20.3530,
      maxLat: 20.3560,
      minLng: 85.8170,
      maxLng: 85.8210,
    ),
    ZoneGeofence(
      zone: CampusZone.ksac,
      minLat: 20.3510,
      maxLat: 20.3540,
      minLng: 85.8130,
      maxLng: 85.8170,
    ),
    ZoneGeofence(
      zone: CampusZone.kpHostels,
      minLat: 20.3560,
      maxLat: 20.3610,
      minLng: 85.8150,
      maxLng: 85.8220,
    ),
    ZoneGeofence(
      zone: CampusZone.foodCourt,
      minLat: 20.3500,
      maxLat: 20.3525,
      minLng: 85.8180,
      maxLng: 85.8230,
    ),
    ZoneGeofence(
      zone: CampusZone.campus6and7,
      minLat: 20.3540,
      maxLat: 20.3600,
      minLng: 85.8100,
      maxLng: 85.8150,
    ),
    ZoneGeofence(
      zone: CampusZone.kims,
      minLat: 20.3450,
      maxLat: 20.3500,
      minLng: 85.8100,
      maxLng: 85.8200,
    ),
  ];

  /// Resolve a coordinate to the first matching KIIT zone.
  ///
  /// Returns [CampusZone.offCampus] when the point is outside every fence.
  static CampusZone resolve(double lat, double lng) {
    for (final fence in all) {
      if (fence.contains(lat, lng)) return fence.zone;
    }
    return CampusZone.offCampus;
  }

  static ZoneGeofence? fenceFor(CampusZone zone) {
    for (final fence in all) {
      if (fence.zone == zone) return fence;
    }
    return null;
  }
}
