import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

/// `GET /health` — is core answering, and what is it.
///
/// Shared rather than private to the System screen because Administration's
/// header carries it above every section: the one fact true of Administration
/// as a whole rather than of any screen inside it. Two private copies would
/// also mean two requests for the same answer on the same frame.
final systemHealthProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.read(homecoreClientProvider);
  final response = await client.dio.get('/health');
  return Map<String, dynamic>.from(response.data as Map);
});

/// `GET /system/status` — counts, database sizes, uptime.
final systemStatusProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.read(homecoreClientProvider);
  final response = await client.dio.get('/system/status');
  return Map<String, dynamic>.from(response.data as Map);
});

/// `6211` → `1h 43m`. Uptime is read at a glance, so the seconds are noise and
/// a bare count of them is not a duration anybody parses.
String formatUptime(num seconds) {
  final s = seconds.round();
  final days = s ~/ 86400;
  final hours = (s % 86400) ~/ 3600;
  final minutes = (s % 3600) ~/ 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}
