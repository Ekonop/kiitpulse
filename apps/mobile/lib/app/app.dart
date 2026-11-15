import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kiit_ui/kiit_ui.dart';

import '../features/auth/presentation/gate_screen.dart';
import '../features/passport/presentation/passport_screen.dart';
import '../features/radar/presentation/radar_screen.dart';
import '../core/auth/auth_controller.dart';

/// Root of the app.
///
/// Auth is the gate for the whole shell: switching between [GateScreen] and
/// [HomeShell] is done here rather than with a router, because there is exactly
/// one transition and a full router would be more machinery than the app needs
/// today. `app/router/app_router.dart` takes over when deep links arrive.
class KIITPulseApp extends ConsumerWidget {
  const KIITPulseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final signedIn = auth is SignedIn;

    return MaterialApp(
      title: 'KIITPulse',
      debugShowCheckedModeBanner: false,
      theme: PulseTheme.darkTheme,
      darkTheme: PulseTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: AnimatedSwitcher(
        duration: PulseMotion.base,
        switchInCurve: PulseMotion.enter,
        switchOutCurve: PulseMotion.exit,
        child: signedIn
            ? const HomeShell(key: ValueKey('shell'))
            : const GateScreen(key: ValueKey('gate')),
      ),
    );
  }
}

/// Two destinations, not five.
///
/// The radar is where students live; the passport is what they come back for.
/// Anything else would need a tab it has not earned.
///
/// The shell adapts rather than stretching: a phone gets a bottom bar, a
/// browser gets a side rail. Same destinations, same order - only the axis
/// changes, so muscle memory survives switching devices.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  void _select(int i) {
    setState(() => _index = i);
    // Badges are earned from activity elsewhere in the app, and the passport
    // stays mounted inside the IndexedStack. Nudge it to re-read when shown.
    if (i == 1) {
      ref.read(passportRefreshProvider.notifier).state++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = pulseFormFactorOf(context);

    // One IndexedStack either way: switching destinations must not rebuild a
    // screen or drop an open socket.
    final pages = IndexedStack(
      index: _index,
      children: const [
        RadarScreen(),
        PassportScreen(),
      ],
    );

    if (form.usesSideRail) {
      return Scaffold(
        body: Row(
          children: [
            _PulseNavRail(
              index: _index,
              onChanged: _select,
            ),
            Expanded(child: pages),
          ],
        ),
      );
    }

    return Scaffold(
      body: pages,
      bottomNavigationBar: _PulseNavBar(
        index: _index,
        onChanged: _select,
      ),
    );
  }
}

/// Destinations, named once so the bar and the rail cannot drift apart.
const _destinations = [
  (icon: Icons.radar_rounded, label: 'Radar'),
  (icon: Icons.workspace_premium_outlined, label: 'Passport'),
];

/// The wide-window navigation: a vertical rail with room for a wordmark.
///
/// A browser has horizontal room to spare and almost no vertical room to
/// waste, so navigation moves to the side where a mouse and a thumb both
/// reach it comfortably.
class _PulseNavRail extends StatelessWidget {
  const _PulseNavRail({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pulse-nav-rail'),
      width: PulseBreakpoints.railWidth,
      decoration: const BoxDecoration(
        color: PulsePalette.deepObsidian,
        border: Border(right: BorderSide(color: PulsePalette.borderGrey)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 22, 22, 30),
              child: _RailWordmark(),
            ),
            for (var i = 0; i < _destinations.length; i++)
              _RailItem(
                icon: _destinations[i].icon,
                label: _destinations[i].label,
                selected: index == i,
                onTap: () => onChanged(i),
              ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _RailWordmark extends StatelessWidget {
  const _RailWordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: PulsePalette.kiitEmerald,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 9),
        Text(
          'KIITPULSE',
          style: PulseType.display(15).copyWith(letterSpacing: 1.6),
        ),
      ],
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = selected ? PulsePalette.kiitEmerald : PulsePalette.textTertiary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: PulsePalette.kiitEmerald.withValues(alpha: 0.06),
          highlightColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: selected
                  ? PulsePalette.kiitEmerald.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(icon, size: 19, color: tint),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: PulseType.body(13.5, weight: FontWeight.w600)
                      .copyWith(color: tint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseNavBar extends StatelessWidget {
  const _PulseNavBar({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pulse-nav-bar'),
      decoration: const BoxDecoration(
        color: PulsePalette.deepObsidian,
        border: Border(top: BorderSide(color: PulsePalette.borderGrey)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              for (var i = 0; i < _destinations.length; i++)
                _NavItem(
                  icon: _destinations[i].icon,
                  label: _destinations[i].label,
                  selected: index == i,
                  onTap: () => onChanged(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint =
        selected ? PulsePalette.kiitEmerald : PulsePalette.textTertiary;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          splashColor: PulsePalette.kiitEmerald.withValues(alpha: 0.06),
          highlightColor: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1 : 0.94,
                duration: PulseMotion.fast,
                child: Icon(icon, size: 19, color: tint),
              ),
              const SizedBox(height: 3),
              Text(
                label.toUpperCase(),
                style: PulseType.telemetry(8).copyWith(
                  color: tint,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
