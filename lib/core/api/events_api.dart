import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/hc_event.dart';

class EventsApi {
  WebSocketChannel? _channel;
  StreamController<HcEvent>? _controller;

  Stream<HcEvent> connect() {
    _controller?.close();
    _controller = StreamController<HcEvent>.broadcast();
    _reconnect();
    return _controller!.stream;
  }

  void _reconnect() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return;

    // Use the browser's current host so this works behind a reverse proxy
    final wsScheme = Uri.base.scheme == 'https' ? 'wss' : 'ws';
    final uri = Uri.parse(
        '$wsScheme://${Uri.base.host}:${Uri.base.port}/api/v1/events/stream?token=$token');

    try {
      _channel = WebSocketChannel.connect(uri);
      _channel!.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            final event = HcEvent.fromJson(json);
            _controller?.add(event);
          } catch (_) {}
        },
        onError: (e) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
      );
    } catch (e) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    Future.delayed(const Duration(seconds: 3), _reconnect);
  }

  void dispose() {
    _channel?.sink.close();
    _controller?.close();
  }
}
