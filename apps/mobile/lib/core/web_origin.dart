import 'package:flutter/foundation.dart' show kIsWeb;

import 'web_origin_stub.dart'
    if (dart.library.js_interop) 'web_origin_web.dart';

/// The base URL the live backend is reachable at.
///
/// On web the app is served by the same Go process that answers the API, so the
/// correct host is whatever the browser used. Reading it at runtime instead of
/// baking it in means the same build works on localhost, on a laptop's LAN
/// address, and behind a tunnel - none of which the build can know in advance.
///
/// Elsewhere there is no such implicit origin, so the compile-time value is used
/// and must be an absolute URL.
String resolveApiBaseUrl(String configured) {
  if (!kIsWeb) return configured;

  final origin = webOrigin();
  if (origin.isEmpty) return configured;

  // A configured absolute URL still wins: someone may deliberately point a
  // build at a different backend.
  if (configured.startsWith('http://') || configured.startsWith('https://')) {
    return configured;
  }
  return origin;
}
