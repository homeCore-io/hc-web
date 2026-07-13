import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../schema/plugin_capabilities.dart';

/// Browser implementation — see `action_stream.dart` for the contract.
Stream<ActionEvent> openActionStream({
  required String pluginId,
  required String requestId,
  required String token,
}) {
  final url = '/api/v1/plugins/$pluginId/command/$requestId/stream'
      '?token=${Uri.encodeQueryComponent(token)}';

  final controller = StreamController<ActionEvent>();
  final source = web.EventSource(url);

  void close() {
    source.close();
    if (!controller.isClosed) controller.close();
  }

  // Core names the SSE event "stream" rather than using the default "message",
  // so listening on onMessage alone would receive nothing.
  source.addEventListener(
    'stream',
    (web.Event event) {
      final data = (event as web.MessageEvent).data.dartify();
      if (data is! String) return;

      final ActionEvent parsed;
      try {
        parsed = ActionEvent.fromJson(jsonDecode(data) as Map);
      } on FormatException {
        return; // a keep-alive or a frame we don't understand
      }

      controller.add(parsed);

      // Every terminal stage ends the run, not just `complete`.
      if (parsed.stage.isTerminal) close();
    }.toJS,
  );

  // An SSE error also fires when the server closes the stream normally, so this
  // must not be reported as a failure — the terminal stage above already told
  // us how the run ended.
  source.onerror = (web.Event _) {
    close();
  }.toJS;

  controller.onCancel = close;
  return controller.stream;
}
