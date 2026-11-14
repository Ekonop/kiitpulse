import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:kiit_ui/kiit_ui.dart';

import '../../../../core/native/proximity_guard.dart';
import '../../../../core/zone/zone_selection.dart';

/// Header telemetry: where you are, how many students are here, and whether
/// the location is trusted.
///
/// The three readings are deliberately instrument-like (monospaced, uppercase)
/// because they are measurements, not decoration. The verified chip is the
/// only place the app makes a security claim, so it is explicit about which
/// claim it is making.
class RadarHeader extends StatelessWidget {
  const RadarHeader({
    super.key,
    required this.selection,
    required this.population,
    required this.proximity,
  });

  final ZoneSelection selection;
  final int? population;
  final AsyncValue<ProximityResult> proximity;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const _PulseDot(),
                        const SizedBox(width: 8),
                        Text(
                          'KIIT CAMPUS RADAR',
                          style: PulseType.telemetry(11).copyWith(
                            color: PulsePalette.kiitEmerald,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      selection.label,
                      style: PulseType.display(23).copyWith(
                        color: PulsePalette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      selection.subtitle,
                      style: PulseType.body(12.5).copyWith(
                        color: PulsePalette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _PopulationReadout(count: population),
            ],
          ),
          const SizedBox(height: 12),
          _TrustChip(proximity: proximity, selection: selection),
        ],
      ),
    );
  }
}

class _PopulationReadout extends StatelessWidget {
  const _PopulationReadout({required this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final value = count;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedCounter(
          value: value,
          builder: (context, animated) => Text(
            animated == null ? '--' : '$animated',
            style: PulseType.telemetry(19).copyWith(
              color: PulsePalette.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'ACTIVE HERE',
          style: PulseType.telemetry(8.5).copyWith(
            color: PulsePalette.textTertiary,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Says exactly what was verified, and says nothing more.
class _TrustChip extends StatelessWidget {
  const _TrustChip({required this.proximity, required this.selection});

  final AsyncValue<ProximityResult> proximity;
  final ZoneSelection selection;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: PulseMotion.base,
      switchInCurve: PulseMotion.enter,
      switchOutCurve: PulseMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
      // Keying on the resolved status makes the chip cross-fade only when the
      // trust state actually changes, not on every radar tick.
      child: KeyedSubtree(
        key: ValueKey(_stateKey()),
        child: _resolve(),
      ),
    );
  }

  String _stateKey() {
    if (proximity.isLoading) return 'loading';
    if (proximity.hasError) return 'error';
    return proximity.valueOrNull?.status.name ?? 'unknown';
  }

  Widget _resolve() {
    return proximity.when(
      loading: () => const _Chip(
        icon: Icons.gps_fixed_rounded,
        label: 'VERIFYING LOCATION',
        tint: PulsePalette.textTertiary,
      ),
      error: (_, __) => const _Chip(
        icon: Icons.gps_off_rounded,
        label: 'LOCATION UNAVAILABLE',
        tint: PulsePalette.coralStage,
      ),
      data: (result) {
        switch (result.status) {
          case LocationSecurityLevel.verified:
            final metres = result.accuracyMetres;
            // The word "hardware" is a claim, and on web it is false: the
            // browser's Geolocation API has no mock-provider flag and no
            // hardware attestation, so saying "hardware verified" would be
            // overstating what we know. Say what actually happened.
            final prefix = kIsWeb ? 'BROWSER LOCATION' : 'HARDWARE VERIFIED';
            return _Chip(
              icon: Icons.verified_rounded,
              label: metres == null
                  ? prefix
                  : '$prefix · ±${metres.round()} M',
              tint: PulsePalette.kiitEmerald,
            );
          case LocationSecurityLevel.mockDetected:
            return const _Chip(
              icon: Icons.warning_amber_rounded,
              label: 'MOCK GPS DETECTED',
              tint: PulsePalette.coralStage,
            );
          case LocationSecurityLevel.permissionDenied:
            return const _Chip(
              icon: Icons.lock_outline_rounded,
              label: 'LOCATION PERMISSION NEEDED',
              tint: PulsePalette.amberWarn,
            );
          case LocationSecurityLevel.hardwareUnavailable:
            return const _Chip(
              icon: Icons.gps_off_rounded,
              label: 'NO LOCATION HARDWARE',
              tint: PulsePalette.amberWarn,
            );
          case LocationSecurityLevel.outsideCampus:
            return const _Chip(
              icon: Icons.wrong_location_outlined,
              label: 'OUTSIDE PATIA GEOFENCE · READ ONLY',
              tint: PulsePalette.amberWarn,
            );
        }
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.tint});

  final IconData icon;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tint),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: PulseType.telemetry(9.5).copyWith(
                color: tint,
                letterSpacing: 0.9,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The breathing emerald dot that says "the radar is live".
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_c.value);
        return SizedBox(
          width: 12,
          height: 12,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t) * 0.5,
                child: Container(
                  width: 12 * (0.4 + t * 0.6),
                  height: 12 * (0.4 + t * 0.6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: PulsePalette.kiitEmerald,
                      width: 1,
                    ),
                  ),
                ),
              ),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: PulsePalette.kiitEmerald,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
