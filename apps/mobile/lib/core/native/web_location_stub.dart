import 'web_location.dart';

/// Non-web platforms have no `navigator.geolocation`.
const bool kWebGeolocationAvailable = false;

/// Never called on non-web platforms: the guard checks availability first.
Future<WebLocationFix?> requestWebLocation() async => null;
