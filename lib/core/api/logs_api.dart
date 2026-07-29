import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/log_entry.dart';

class LogsApi {
  WebSocketChannel? _channel;
  StreamController<LogEntry>? _controller;
  final StreamController<bool> _connectedController =
      StreamController<bool>.broadcast();

  String _level = 'debug';
  String? _target;

  Stream<bool> get connectionState => _connectedController.stream;

  Stream<LogEntry> connect({String level = 'debug', String? target}) {
    _level = level;
    _target = target;
    _controller?.close();
    _controller = StreamController<LogEntry>.broadcast();
    _reconnect();
    return _controller!.stream;
  }

  void _reconnect() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return;

    final wsScheme = Uri.base.scheme == 'https' ? 'wss' : 'ws';
    var path = '/api/v1/logs/stream?token=$token&level=$_level&history=100';
    if (_target != null) path += '&target=${Uri.encodeComponent(_target!)}';
    final uri = Uri.parse('$wsScheme://${Uri.base.host}:${Uri.base.port}$path');

    try {
      _channel = WebSocketChannel.connect(uri);
      _connectedController.add(true);
      _channel!.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            _controller?.add(LogEntry.fromJson(json));
          } catch (_) {}
        },
        onError: (_) {
          _connectedController.add(false);
          _scheduleReconnect();
        },
        onDone: () {
          _connectedController.add(false);
          _scheduleReconnect();
        },
      );
    } catch (_) {
      _connectedController.add(false);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    Future.delayed(const Duration(seconds: 5), _reconnect);
  }

  void dispose() {
    _channel?.sink.close();
    _controller?.close();
    _connectedController.close();
  }
}
