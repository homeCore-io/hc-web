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

/// `GET /system/versions` — every component's version, not just core's.
///
/// The point of the component_versioning work: core, the SDK and each plugin
/// carry their own SemVer, so "what is this house running" has more than one
/// answer. In a container this is the BOM the image build wrote; a plain
/// binary reports just its own version, which is honest — nothing else was
/// packaged with it.
final systemVersionsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.read(homecoreClientProvider);
  final response = await client.dio.get('/system/versions');
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
