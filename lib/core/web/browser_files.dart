/// Getting bytes out of, and into, the browser.
///
/// The implementation is chosen at compile time: the real DOM in a browser, a
/// no-op off it. hc-web only ever runs in a browser, so the stub is never
/// reached at runtime — it exists so `lib/app.dart` can be imported by a VM
/// test, which it could not be while this file pulled `dart:js_interop`
/// straight into the settings page.
///
/// That was not a theoretical cost. `lib/app.dart` holds the router, the auth
/// redirect and the notifier that drives it, and none of it could be reached
/// by a test — which is how a Sign out button that did nothing shipped.
library;

export 'browser_files_types.dart';
export 'browser_files_stub.dart'
    if (dart.library.js_interop) 'browser_files_web.dart';
