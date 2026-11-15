import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kiit_contracts/kiit_contracts.dart';
import 'package:kiit_ui/kiit_ui.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/providers.dart';

final badgesProvider = FutureProvider.autoDispose<List<FoilBadge>>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return const [];

  // The shell keeps every screen alive in an IndexedStack, so autoDispose never
  // fires while the app is open. Without this, a student earns a badge and the
  // passport keeps showing the list it fetched the first time the tab was
  // built. Watching the visible destination makes the list refetch on entry.
  ref.watch(passportRefreshProvider);

  return ref.watch(pulseGatewayProvider).fetchBadges(session.rollNumber);
});

/// Bumped whenever the passport becomes visible, so [badgesProvider] re-reads.
final passportRefreshProvider = StateProvider<int>((ref) => 0);

/// Profile and KIIT foil passport.
///
/// The badges are the retention loop. Each one is issued by the server from
/// activity it observed (messages sent, stages joined, zones visited) and states
/// that evidence in its own caption. They are deliberately *not* presented as
/// event attendance: this deployment has no attendance feed and cannot verify
/// who turned up to KIIT Fest. Rendered with the gyro-reactive foil shader; the
/// grid keeps the aspect ratio fixed at 160x220 so the shader never has to
/// letterbox.
class PassportScreen extends ConsumerWidget {
  const PassportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final badges = ref.watch(badgesProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _PassportHeader(
                rollNumber: session?.rollNumber ?? '——',
                branchTag: session?.branchTag ?? 'KIIT Student',
                badgeCount: badges.valueOrNull?.length ?? 0,
              ),
            ),
            badges.when(
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: PulsePalette.kiitEmerald,
                    ),
                  ),
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load your passport: $e',
                    style: PulseType.body(12.5)
                        .copyWith(color: PulsePalette.coralStage),
                  ),
                ),
              ),
              data: (list) => list.isEmpty
                  ? const SliverToBoxAdapter(child: _EmptyPassport())
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 100),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 160 / 220,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final badge = list[i];
                            return FadeSlideIn(
                              index: i,
                              child: FoilPassportCard(
                                badgeName: badge.label,
                                subtitle: badge.eventName ?? badge.type,
                                accentColor: Color(badge.accentArgb),
                                issuedAt: badge.issuedAt,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            );
                          },
                          childCount: list.length,
                        ),
                      ),
                    ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: PulsePalette.raisedSurface,
                    foregroundColor: PulsePalette.textSecondary,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).signOut(),
                  child: const Text('Sign out'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PassportHeader extends StatelessWidget {
  const _PassportHeader({
    required this.rollNumber,
    required this.branchTag,
    required this.badgeCount,
  });

  final String rollNumber;
  final String branchTag;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'KIIT PASSPORT',
            style: PulseType.telemetry(10).copyWith(
              color: PulsePalette.kiitEmerald,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PulsePalette.elevatedSurface,
                  border: Border.all(
                    color: PulsePalette.kiitEmerald.withValues(alpha: 0.4),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  rollNumber.length >= 2
                      ? rollNumber.substring(0, 2).toUpperCase()
                      : 'KI',
                  style: PulseType.telemetry(16).copyWith(
                    color: PulsePalette.kiitEmerald,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rollNumber,
                      style: PulseType.display(19)
                          .copyWith(color: PulsePalette.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$branchTag · $badgeCount collectible'
                      '${badgeCount == 1 ? '' : 's'}',
                      style: PulseType.body(12)
                          .copyWith(color: PulsePalette.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: PulsePalette.elevatedSurface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: PulsePalette.borderGrey),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 13, color: PulsePalette.kiitEmerald),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Each badge is awarded from activity this campus server '
                    'observed, and says what earned it. Tilt the phone to '
                    'catch the foil.',
                    style: PulseType.body(11)
                        .copyWith(color: PulsePalette.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when a student has not earned a badge yet.
///
/// A blank grid reads as a loading failure. This says what the passport is for
/// and how to earn the first mark, so a first-day student is not left guessing.
class _EmptyPassport extends StatelessWidget {
  const _EmptyPassport();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 48, 28, 0),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: PulsePalette.raisedSurface,
              shape: BoxShape.circle,
              border: Border.all(color: PulsePalette.borderGrey),
            ),
            child: const Icon(
              Icons.workspace_premium_outlined,
              size: 27,
              color: PulsePalette.textTertiary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No stamps yet',
            style: PulseType.display(16).copyWith(
              color: PulsePalette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your passport fills up as you show up. Join a voice huddle, '
            'answer a question that helps someone, or turn up at a KSAC night '
            'to earn your first stamp.',
            textAlign: TextAlign.center,
            style: PulseType.body(12).copyWith(
              color: PulsePalette.textTertiary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
