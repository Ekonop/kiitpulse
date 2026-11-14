import 'package:kiit_contracts/kiit_contracts.dart';

import '../native/proximity_guard.dart';

/// The zone the radar is currently scoped to.
///
/// `null` means "All Patia": the combined feed across every physical zone.
/// This is the single source of truth for the zone pill control and the header
/// telemetry, so they can never disagree.
class ZoneSelection {
  const ZoneSelection({this.zone, this.detected});

  /// Selected filter. `null` = all Patia.
  final CampusZone? zone;

  /// What the device actually resolved to, used for the "verified" chip.
  final CampusZone? detected;

  bool get isAll => zone == null;

  /// What the radar should query. When "all" is selected we still need one
  /// zone key for the transport, so we read the detected zone and let the
  /// repository fan out.
  CampusZone get effectiveZone => zone ?? detected ?? CampusZone.campus15;

  String get label => zone?.label ?? 'All Patia';

  String get subtitle => zone?.subtitle ?? 'Whole campus';

  ZoneSelection copyWith({CampusZone? zone, bool clearZone = false, CampusZone? detected}) {
    return ZoneSelection(
      zone: clearZone ? null : (zone ?? this.zone),
      detected: detected ?? this.detected,
    );
  }
}

/// Where the app is in its proximity verification lifecycle.
sealed class ProximityState {
  const ProximityState();
}

class ProximityChecking extends ProximityState {
  const ProximityChecking();
}

class ProximityResolved extends ProximityState {
  const ProximityResolved(this.result);

  final ProximityResult result;
}

class ProximityBlocked extends ProximityState {
  const ProximityBlocked(this.reason, {this.canRetry = true});

  final String reason;
  final bool canRetry;
}
