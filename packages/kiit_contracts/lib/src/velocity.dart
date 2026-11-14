import 'dart:math' as math;

/// The campus velocity score.
///
///   V = (Σ M·w_m + R·w_r + L·w_l) / Δt^γ
///
/// with weights MESSAGE=1.0, REACTION=0.25, VOICE_JOIN=3.5 and γ=1.5.
///
/// The server is the source of truth (Redis ZINCRBY + a 1-minute 0.85 decay
/// cron). This file exists so the *client* can predict the score between
/// ticks without waiting for the socket, and so the maths is unit-testable in
/// one language instead of two.
abstract final class Velocity {
  static const double messageWeight = 1.0;
  static const double reactionWeight = 0.25;
  static const double voiceJoinWeight = 3.5;

  /// Time decay exponent.
  static const double gamma = 1.5;

  /// Per-minute multiplicative decay applied by the cron job.
  static const double decayFactor = 0.85;

  /// Topics below this raw score are purged from the ZSET.
  static const double purgeFloor = 0.1;

  /// Topics expire this long after their last engagement spike.
  static const Duration topicTtl = Duration(hours: 24);

  /// Raw weighted event sum.
  static double rawScore({
    required int messages,
    required int reactions,
    required int voiceJoins,
  }) =>
      messages * messageWeight +
      reactions * reactionWeight +
      voiceJoins * voiceJoinWeight;

  /// Full score including the time-decay denominator.
  ///
  /// [elapsed] is measured from the topic's creation (the denominator is the
  /// age of the conversation, not the gap since the last message). A `Δt` under
  /// one minute is clamped to one minute so a brand-new topic does not divide
  /// by ~zero and explode to infinity.
  static double score({
    required int messages,
    required int reactions,
    required int voiceJoins,
    required Duration elapsed,
  }) =>
      rawScore(
        messages: messages,
        reactions: reactions,
        voiceJoins: voiceJoins,
      ) /
      decayDenominator(elapsed);

  static double decayDenominator(Duration elapsed) {
    final minutes = math.max(elapsed.inMilliseconds / 60000.0, 1.0);
    return math.pow(minutes, gamma).toDouble();
  }

  /// What the score becomes after [minutes] of the decay cron.
  static double afterDecay(double current, int minutes) =>
      current * math.pow(decayFactor, minutes).toDouble();

  /// Score with one more event of [kind] folded in, without touching state.
  static double withEvent(
    double current, {
    required VelocityEventKind kind,
    int count = 1,
  }) =>
      current + _weightOf(kind) * count;

  static double _weightOf(VelocityEventKind kind) {
    switch (kind) {
      case VelocityEventKind.message:
        return messageWeight;
      case VelocityEventKind.reaction:
        return reactionWeight;
      case VelocityEventKind.voiceJoin:
        return voiceJoinWeight;
    }
  }
}

enum VelocityEventKind { message, reaction, voiceJoin }

/// Human label for a score, used by the radar card footer.
String velocityLabel(double score) {
  if (score >= 150) return 'SURGING';
  if (score >= 80) return 'HOT';
  if (score >= 30) return 'RISING';
  if (score >= 10) return 'WARM';
  return 'COOLING';
}
