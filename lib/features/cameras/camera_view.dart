/// A camera shown live — an iframe or a refreshing image.
///
/// See `camera_still.dart` for why this is split.
library;

export 'camera_view_stub.dart'
    if (dart.library.js_interop) 'camera_view_web.dart';
