import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kiit_api_client/kiit_api_client.dart';
import 'package:kiit_contracts/kiit_contracts.dart';

import '../../../core/native/proximity_guard.dart';
import '../../../core/providers.dart';
import '../../../core/zone/zone_selection.dart';

final proximityGuardProvider = Provider<ProximityGuard>((ref) {
  return ProximityGuard();
});

/// Runs once, on entering the radar. The result gates the feed.
final proximityProvider = FutureProvider<ProximityResult>((ref) {
  return ref.watch(proximityGuardProvider).verifyDeviceLocation();
});

/// Zone selection for the radar. Starts on "All Patia"; the first successful
/// proximity check narrows it to the detected zone so a student landing in
/// Campus 15 is not made to tap a pill before seeing their own corridor.
class ZoneSelectionController extends StateNotifier<ZoneSelection> {
  ZoneSelectionController() : super(const ZoneSelection());

  void select(CampusZone? zone) {
    state = zone == null
        ? state.copyWith(clearZone: true)
        : state.copyWith(zone: zone);
  }

  void adoptDetected(CampusZone detected) {
    if (state.detected == detected) return;
    state = ZoneSelection(
      zone: state.zone ?? (detected.isPhysical ? detected : null),
      detected: detected,
    );
  }
}

final zoneSelectionProvider =
    StateNotifierProvider<ZoneSelectionController, ZoneSelection>((ref) {
  return ZoneSelectionController();
});

/// Live topic list for the selected zone.
///
/// When "All Patia" is selected we merge every physical zone and sort by
/// velocity. Merging in the repository (not the widget) keeps the list stable
/// across rebuilds and means the sort rule lives in one place.
final radarProvider = StreamProvider<List<TopicPulse>>((ref) {
  final gateway = ref.watch(pulseGatewayProvider);
  final selection = ref.watch(zoneSelectionProvider);

  if (selection.zone != null) {
    return gateway.watchRadar(selection.zone!);
  }
  return _allPatia(gateway);
});

Stream<List<TopicPulse>> _allPatia(PulseGateway gateway) {
  // One broadcast fan-in: emit whenever any zone changes.
  final zones = CampusZone.physical;
  late final controller = StreamController<List<TopicPulse>>();
  final latest = <CampusZone, List<TopicPulse>>{};
  final subs = <StreamSubscription<List<TopicPulse>>>[];
  var closed = false;

  void emit() {
    if (closed) return;
    final merged = [
      for (final z in zones) ...?latest[z],
    ]..sort((a, b) => b.velocityScore.compareTo(a.velocityScore));
    controller.add(merged);
  }

  controller.onListen = () {
    for (final zone in zones) {
      subs.add(gateway.watchRadar(zone).listen((topics) {
        latest[zone] = topics;
        emit();
      }));
    }
  };
  controller.onCancel = () async {
    closed = true;
    for (final s in subs) {
      await s.cancel();
    }
    await controller.close();
  };

  return controller.stream;
}

/// Student count for the selected zone, or the sum across Patia.
final zonePopulationProvider = StreamProvider<int>((ref) {
  final gateway = ref.watch(pulseGatewayProvider);
  final selection = ref.watch(zoneSelectionProvider);
  if (selection.zone != null) {
    return gateway.watchZonePopulation(selection.zone!);
  }
  return _sumPopulation(gateway);
});

Stream<int> _sumPopulation(PulseGateway gateway) {
  late final controller = StreamController<int>();
  final latest = <CampusZone, int>{};
  final subs = <StreamSubscription<int>>[];
  var closed = false;

  void emit() {
    if (closed) return;
    controller.add(latest.values.fold<int>(0, (a, b) => a + b));
  }

  controller.onListen = () {
    for (final zone in CampusZone.physical) {
      subs.add(gateway.watchZonePopulation(zone).listen((count) {
        latest[zone] = count;
        emit();
      }));
    }
  };
  controller.onCancel = () async {
    closed = true;
    for (final s in subs) {
      await s.cancel();
    }
    await controller.close();
  };

  return controller.stream;
}
