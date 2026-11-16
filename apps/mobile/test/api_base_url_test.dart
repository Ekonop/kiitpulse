import 'package:flutter_test/flutter_test.dart';
import 'package:kiitpulse/core/web_origin.dart';

/// The live web build must reach the API on whatever host the browser used.
///
/// Baking an absolute URL into the build is what made the public deployment
/// fragile: the same bundle has to work on localhost, on a LAN address and
/// behind a tunnel, and none of those can be known at build time.
void main() {
  group('resolveApiBaseUrl', () {
    test('an explicit absolute URL always wins', () {
      // Someone pointing a build at a separate backend must not be overridden.
      expect(
        resolveApiBaseUrl('https://api.kiitpulse.app'),
        'https://api.kiitpulse.app',
      );
      expect(
        resolveApiBaseUrl('http://127.0.0.1:8080'),
        'http://127.0.0.1:8080',
      );
    });

    test('non-web keeps the configured URL, even a relative one', () {
      // Tests and mobile runs have no browser origin to fall back to, so the
      // value must pass through untouched rather than becoming empty.
      expect(resolveApiBaseUrl(''), '');
      expect(resolveApiBaseUrl('/'), '/');
    });
  });
}
