import '../schema/plugin_capabilities.dart';

/// Non-web fallback. hc-web only ever runs in a browser; this exists so the VM
/// test runner can compile the library that imports it.
Stream<ActionEvent> openActionStream({
  required String pluginId,
  required String requestId,
  required String token,
}) =>
    Stream.error(
      UnsupportedError(
          'Streaming plugin actions require a browser EventSource'),
    );
