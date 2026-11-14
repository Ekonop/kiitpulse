import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kiit_api_client/kiit_api_client.dart';
import '../providers.dart';

/// Session state for the whole app.
///
/// Only two things are true here: you are signed in with a verified
/// @kiit.ac.in identity, or you are not. Everything downstream reads
/// [sessionProvider] and assumes a valid session; the router guarantees that.
sealed class AuthState {
  const AuthState();
}

class SignedOut extends AuthState {
  const SignedOut({this.error});

  /// Last failure, so the gate can explain itself without a snackbar queue.
  final String? error;
}

class SigningIn extends AuthState {
  const SigningIn();
}

class SignedIn extends AuthState {
  const SignedIn(this.session);

  final Session session;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._gateway) : super(const SignedOut());

  final PulseGateway _gateway;

  /// Campus domain. Anything else is rejected before a network call.
  static const campusDomain = '@kiit.ac.in';

  /// The authenticated session, or a thrown error. Never returns a fake
  /// session: a caller that needs one must handle [SignedOut].
  Session get requireSession {
    final current = state;
    if (current is SignedIn) return current.session;
    throw StateError('No authenticated session; the router should have gated.');
  }

  static bool isValidCampusEmail(String email) {
    final clean = email.trim().toLowerCase();
    if (!clean.endsWith(campusDomain)) return false;
    final local = clean.substring(0, clean.length - campusDomain.length);
    // Roll numbers are digits only; anything else is not a student identity.
    return local.isNotEmpty &&
        RegExp(r'^[0-9]{6,12}$').hasMatch(local);
  }

  /// Roll prefixes to programme tags. Single source of truth: the demo gateway
  /// delegates here so the two can never disagree.
  static String branchTagFor(String roll) {
    final r = roll.trim();
    if (r.startsWith('24155')) return 'CSE-AIML \'28';
    if (r.startsWith('24156')) return 'IT \'28';
    if (r.startsWith('2405')) return 'CSE \'28';
    if (r.startsWith('2406')) return 'IT \'28';
    if (r.startsWith('2305')) return 'CSE \'27';
    if (r.startsWith('2306')) return 'IT \'27';
    if (r.startsWith('22')) return 'Senior';
    return 'KIIT Student';
  }

  Future<bool> signIn(String email) async {
    final clean = email.trim().toLowerCase();
    if (!isValidCampusEmail(clean)) {
      state = const SignedOut(
        error: 'Use your @kiit.ac.in student email (roll number, e.g. '
            '241551058@kiit.ac.in).',
      );
      return false;
    }
    state = const SigningIn();
    try {
      final session = await _gateway.signIn(clean);
      state = SignedIn(session);
      return true;
    } on GatewayException catch (e) {
      state = SignedOut(error: e.message);
      return false;
    } catch (_) {
      state = const SignedOut(
        error: 'Could not reach the campus network. Check your connection.',
      );
      return false;
    }
  }

  void signOut() => state = const SignedOut();
}

final StateNotifierProvider<AuthController, AuthState> authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref.watch(pulseGatewayProvider));
});

/// The active session or null - convenient for read-only UI (displaying a roll
/// number) that should degrade instead of throwing.
final Provider<Session?> currentSessionProvider = Provider<Session?>((ref) {
  final state = ref.watch(authControllerProvider);
  return state is SignedIn ? state.session : null;
});
