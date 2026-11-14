import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'web_location.dart';

/// Whether this browser exposes the Geolocation API.
///
/// Over HTTPS (and on localhost) it is always present, but a browser can be
/// built without it and a sandboxed iframe can be denied it, so the guard
/// checks rather than assumes.
const bool kWebGeolocationAvailable = true;

/// Ask the browser for one location fix.
///
/// Resolves to `null` on denial, timeout or any browser error. The caller turns
/// that into a permission state rather than silently substituting a coordinate:
/// a wrong-but-plausible location is worse than an honest "we could not tell".
Future<WebLocationFix?> requestWebLocation() {
  final completer = Completer<WebLocationFix?>();

  // Browsers can resolve a fix slowly or never - a laptop with no GPS and no
  // Wi-Fi positioning can sit for a minute. Ten seconds is long enough for a
  // real fix and short enough that the radar is not stuck behind a spinner.
  final options = web.PositionOptions(
    enableHighAccuracy: true,
    timeout: 10000,
    maximumAge: 30000,
  );

  void succeed(web.GeolocationPosition position) {
    if (completer.isCompleted) return;
    completer.complete(
      WebLocationFix(
        latitude: position.coords.latitude,
        longitude: position.coords.longitude,
        // Some browsers report accuracy as 0 when they do not know. Treat an
        // unknown accuracy as coarse rather than as perfect.
        accuracyMetres: position.coords.accuracy.toDouble() <= 0
            ? double.infinity
            : position.coords.accuracy.toDouble(),
      ),
    );
  }

  void fail(web.GeolocationPositionError error) {
    if (completer.isCompleted) return;
    completer.complete(null);
  }

  try {
    web.window.navigator.geolocation.getCurrentPosition(
      succeed.toJS,
      fail.toJS,
      options,
    );
  } catch (_) {
    // A blocked or absent API throws synchronously rather than calling back.
    return Future<WebLocationFix?>.value(null);
  }

  return completer.future;
}
