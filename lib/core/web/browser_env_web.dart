import 'package:web/web.dart' as web;

/// The browser's address bar and tab handling.
///
/// Two call sites wanted three lines of `package:web` between them — the wall
/// panel's shareable link, and the plugin descriptor's documentation links.
/// Importing the whole DOM into both files to get them is what made
/// `lib/app.dart` unimportable outside a browser.
String get pageOrigin => web.window.location.origin;

String get pageHostname => web.window.location.hostname;

void openInNewTab(String url) => web.window.open(url, '_blank');
