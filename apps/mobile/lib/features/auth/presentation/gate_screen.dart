import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kiit_ui/kiit_ui.dart';

import '../../../core/auth/auth_controller.dart';

/// The sign-in gate.
///
/// One field, one button, one constraint stated plainly. The domain rule is
/// shown before the user types, not as an error afterwards - an angry red
/// "only @kiit.ac.in" message after a failed attempt is a worse experience than
/// a hint that was visible from the start.
class GateScreen extends ConsumerStatefulWidget {
  const GateScreen({super.key});

  @override
  ConsumerState<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends ConsumerState<GateScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );

  @override
  void initState() {
    super.initState();
    _intro.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await ref
        .read(authControllerProvider.notifier)
        .signIn(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final busy = auth is SigningIn;
    final error = auth is SignedOut ? auth.error : null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AnimatedBuilder(
                animation: _intro,
                builder: (context, child) {
                  final t = Curves.easeOutCubic.transform(_intro.value);
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 18 * (1 - t)),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _RadarMark(),
                    const SizedBox(height: 26),
                    Text(
                      'KIITPulse',
                      style: PulseType.display(34).copyWith(
                        color: PulsePalette.textPrimary,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'What your campus is talking about right now. '
                      'Room for each corridor, stage for each debate, gone in '
                      '24 hours.',
                      style: PulseType.body(13.5).copyWith(
                        color: PulsePalette.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 34),
                    Text(
                      'STUDENT EMAIL',
                      style: PulseType.telemetry(9.5).copyWith(
                        color: PulsePalette.textTertiary,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _controller,
                      focusNode: _focus,
                      enabled: !busy,
                      autocorrect: false,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => busy ? null : _submit(),
                      style: PulseType.body(14.5)
                          .copyWith(color: PulsePalette.textPrimary),
                      decoration: const InputDecoration(
                        hintText: '241551058@kiit.ac.in',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 12, color: PulsePalette.textTertiary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Only @kiit.ac.in roll-number accounts. '
                            'No other domain can join.',
                            style: PulseType.body(11)
                                .copyWith(color: PulsePalette.textTertiary),
                          ),
                        ),
                      ],
                    ),
                    AnimatedSize(
                      duration: PulseMotion.base,
                      alignment: Alignment.topCenter,
                      child: error == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: PulsePalette.coralStage
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: PulsePalette.coralStage
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.error_outline_rounded,
                                        size: 14,
                                        color: PulsePalette.coralStage),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        error,
                                        style: PulseType.body(11.5).copyWith(
                                          color: PulsePalette.coralStage,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF00160A),
                              ),
                            )
                          : const Text('Enter the campus radar'),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: Text(
                        'Ephemeral by design · no follows, no permanent graph',
                        style: PulseType.body(10.5)
                            .copyWith(color: PulsePalette.textTertiary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small animated radar sweep as the brand mark.
class _RadarMark extends StatefulWidget {
  const _RadarMark();

  @override
  State<_RadarMark> createState() => _RadarMarkState();
}

class _RadarMarkState extends State<_RadarMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 62,
      height: 62,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 1; i <= 3; i++)
                Container(
                  width: 62.0 * i / 3,
                  height: 62.0 * i / 3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: PulsePalette.kiitEmerald
                          .withValues(alpha: 0.10 + 0.06 * (3 - i)),
                    ),
                  ),
                ),
              Transform.rotate(
                angle: _c.value * 6.28318530718,
                child: Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 31,
                    height: 31,
                    decoration: BoxDecoration(
                      gradient: SweepGradient(
                        colors: [
                          PulsePalette.kiitEmerald.withValues(alpha: 0.0),
                          PulsePalette.kiitEmerald.withValues(alpha: 0.35),
                        ],
                        stops: const [0.6, 1.0],
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: PulsePalette.kiitEmerald,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}