import 'package:flutter_riverpod/flutter_riverpod.dart';

class ApiErrorEntry {
  final DateTime timestamp;
  final String method;
  final String url;
  final int? statusCode;
  final String body;

  ApiErrorEntry({
    required this.timestamp,
    required this.method,
    required this.url,
    this.statusCode,
    required this.body,
  });
}

class ClientErrorLogNotifier extends StateNotifier<List<ApiErrorEntry>> {
  static const _maxEntries = 100;

  ClientErrorLogNotifier() : super(const []);

  void add(ApiErrorEntry entry) {
    final updated = [...state, entry];
    state = updated.length > _maxEntries
        ? updated.sublist(updated.length - _maxEntries)
        : updated;
  }

  void clear() => state = const [];
}

final clientErrorLogProvider =
    StateNotifierProvider<ClientErrorLogNotifier, List<ApiErrorEntry>>(
  (ref) => ClientErrorLogNotifier(),
);
