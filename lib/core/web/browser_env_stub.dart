/// The browser's address bar and tab handling, off the web.
///
/// hc-web only ever runs in a browser, so this half is never reached at
/// runtime. It exists so `lib/app.dart` can be imported by a VM test — and it
/// could not be, which is why the app's own router had no test and a broken
/// Sign out button shipped. See `browser_env.dart`.
///
/// The values are deliberately obvious rather than plausible. A test that
/// somehow depends on one should say so loudly instead of quietly agreeing
/// with a hostname someone might mistake for real.
String get pageOrigin => 'http://localhost';

String get pageHostname => 'localhost';

void openInNewTab(String url) {}
