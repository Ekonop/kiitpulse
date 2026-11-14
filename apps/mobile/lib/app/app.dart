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
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          RadarScreen(),
          PassportScreen(),
        ],
      ),
      bottomNavigationBar: _PulseNavBar(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
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
              _NavItem(
                icon: Icons.radar_rounded,
                label: 'Radar',
                selected: index == 0,
                onTap: () => onChanged(0),
              ),
              _NavItem(
                icon: Icons.workspace_premium_outlined,
                label: 'Passport',
                selected: index == 1,
                onTap: () => onChanged(1),
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
