import '../schema/plugin_capabilities.dart';

// EventSource only exists in the browser. The stub keeps `flutter test` (which
// runs on the VM) compiling; the web implementation is what ships.
import 'action_stream_stub.dart'
    if (dart.library.js_interop) 'action_stream_web.dart' as impl;

/// Subscribes to a streaming plugin action:
/// `GET /api/v1/plugins/{pluginId}/command/{requestId}/stream` (SSE).
///
/// Auth goes in the query string because [EventSource] cannot set headers — and
/// core supports exactly that on this route. It must be a **JWT**; an `hc_sk_`
/// API key is rejected here, since this path only calls `jwt.validate()`.
///
/// The stream closes on any terminal stage — `complete`, `error`, `canceled` or
/// `timeout` — not merely on `complete`. Core synthesises `timeout` when the
/// action's deadline passes and `error{reason: plugin_offline}` when the plugin
/// drops, so a UI that only waits for `complete` hangs forever on a failed
/// Z-Wave inclusion.
///
/// Events emitted before we subscribe are replayed from core's cache (60s TTL),
/// so a slow render cannot miss the first `progress`.
Stream<ActionEvent> openActionStream({
  required String pluginId,
  required String requestId,
  required String token,
}) =>
    impl.openActionStream(
      pluginId: pluginId,
      requestId: requestId,
      token: token,
    );
