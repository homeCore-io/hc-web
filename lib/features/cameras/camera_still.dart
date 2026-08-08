/// A camera shown as a refreshing still.
///
/// The implementation is chosen at compile time. Both cameras widgets are
/// platform views — a real `<img>` registered with the browser's view registry
/// — because a platform view captures every pointer event in its rectangle and
/// a Flutter gesture detector over one never fires. That is the right design
/// for the web, and it is also `dart:ui_web` in a file the router transitively
/// imports, which is what kept `lib/app.dart` out of every VM test.
library;

export 'camera_still_stub.dart'
    if (dart.library.js_interop) 'camera_still_web.dart';
