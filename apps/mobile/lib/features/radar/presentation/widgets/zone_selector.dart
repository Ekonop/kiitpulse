import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:kiit_ui/kiit_ui.dart';

import '../radar_providers.dart';

/// Horizontal pill control for the zone filter.
///
/// "All Patia" is first and is the only option that fans out across zones.
/// The student's own verified zone carries a small dot so they can always find
/// their way back after exploring.
class ZoneSelector extends ConsumerWidget {
  const ZoneSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(zoneSelectionProvider);
    final controller = ref.read(zoneSelectionProvider.notifier);

    final items = <_ZoneItem>[
      const _ZoneItem(label: 'All Patia', zone: null),
      for (final zone in CampusZone.physical)
        _ZoneItem(label: zone.label, zone: zone),
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final selected = selection.zone == item.zone;
          final isYou = item.zone != null && selection.detected == item.zone;
          return _ZonePill(
            label: item.label,
            selected: selected,
            showsYouMarker: isYou,
            onTap: () => controller.select(item.zone),
          );
        },
      ),
    );
  }
}

class _ZoneItem {
  const _ZoneItem({required this.label, required this.zone});

  final String label;
  final CampusZone? zone;
}

class _ZonePill extends StatelessWidget {
  const _ZonePill({
    required this.label,
    required this.selected,
    required this.showsYouMarker,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool showsYouMarker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: showsYouMarker ? '$label, your current zone' : label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? PulsePalette.kiitEmerald.withValues(alpha: 0.12)
                : PulsePalette.elevatedSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? PulsePalette.kiitEmerald.withValues(alpha: 0.55)
                  : PulsePalette.borderGrey,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showsYouMarker) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: selected
                        ? PulsePalette.kiitEmerald
                        : PulsePalette.textTertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: PulseType.body(
                  12.5,
                  weight: selected ? FontWeight.w600 : FontWeight.w500,
                ).copyWith(
                  color: selected
                      ? PulsePalette.kiitEmerald
                      : PulsePalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
