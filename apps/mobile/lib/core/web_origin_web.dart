import 'dart:js_interop';

@JS('window.location.origin')
external JSString? get _jsOrigin;

/// The scheme://host:port the page was loaded from.
///
/// Returns an empty string rather than the literal "null" that an undefined JS
/// string can stringify to, so callers fall back cleanly.
String webOrigin() {
  try {
    final value = _jsOrigin;
    if (value == null) return '';
    final origin = value.toDart;
    if (origin.isEmpty || origin == 'null') return '';
    return origin;
  } catch (_) {
    return '';
  }
}
