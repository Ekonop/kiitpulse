import 'package:kiit_contracts/kiit_contracts.dart';

/// Whether a stage token points at a server that can actually be reached.
///
/// A non-empty string is not the same thing as a server. A demo token carries a
/// `.invalid` host - RFC 2606 reserves the TLD precisely so it can never
/// resolve - and dialling it would start LiveKit's reconnect timers against a
/// host that is guaranteed to fail. That is a hang for the student and a leaked
/// timer in tests, so the check is shared rather than inlined.
///
/// Kept free of Flutter imports so it can be tested without a widget binding.
bool isDialableStageToken(StageToken token) {
  if (token.token.isEmpty || token.wsUrl.isEmpty) return false;
  final host = Uri.tryParse(token.wsUrl)?.host ?? '';
  if (host.isEmpty) return false;
  return !(host == 'invalid' || host.endsWith('.invalid'));
}
