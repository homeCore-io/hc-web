import 'package:dio/dio.dart';

import 'homecore_client.dart';

/// `homecore.toml` as core serves it: the file itself, a parsed view to bind
/// controls against, and where it lives on disk.
class SystemConfig {
  const SystemConfig({
    required this.raw,
    required this.parsed,
    required this.path,
  });

  /// The file, verbatim — comments, ordering and all. The raw editor shows
  /// this, and a raw save writes it back whole.
  final String raw;

  /// The same file as nested JSON. This is what the descriptor's dotted keys
  /// address, and what a patch is diffed against.
  final Map<String, dynamic> parsed;

  /// Absolute path on the server, shown so an operator knows which file they
  /// are editing when they have more than one house.
  final String path;

  factory SystemConfig.fromJson(Map<String, dynamic> j) => SystemConfig(
        raw: j['raw'] as String? ?? '',
        parsed: j['parsed'] is Map
            ? Map<String, dynamic>.from(j['parsed'] as Map)
            : <String, dynamic>{},
        path: j['path'] as String? ?? '',
      );
}

/// The result of a write: core says whether the change needs a restart.
class ConfigSaveResult {
  const ConfigSaveResult({required this.raw, required this.restartRequired});
  final String raw;
  final bool restartRequired;

  factory ConfigSaveResult.fromJson(Map<String, dynamic> j) => ConfigSaveResult(
        raw: j['raw'] as String? ?? '',
        // Absent means "assume yes" — the safe reading, and what core sends.
        restartRequired: j['restart_required'] as bool? ?? true,
      );
}

class SystemConfigApi {
  SystemConfigApi(this.client);
  final HomecoreClient client;

  Future<SystemConfig> get() async {
    final res = await client.dio.get('/system/config');
    return SystemConfig.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// The descriptor: how to present the file. Same envelope as a plugin's, so
  /// the same renderer draws both.
  Future<Map<String, dynamic>> descriptor() async {
    final res = await client.dio.get('/system/config/descriptor');
    final body = Map<String, dynamic>.from(res.data as Map);
    return Map<String, dynamic>.from(body['descriptor'] as Map);
  }

  /// Write only what changed.
  ///
  /// [patch] is nested by section — `{"server": {"port": 8090}}` — which is
  /// what core's `apply_section_patch` merges field by field through
  /// `toml_edit`, leaving comments, ordering and every untouched section
  /// exactly as they were. Sending the whole file instead would reformat it.
  Future<ConfigSaveResult> patch(Map<String, dynamic> patch) async {
    final res = await client.dio.put('/system/config', data: {'patch': patch});
    return ConfigSaveResult.fromJson(
        Map<String, dynamic>.from(res.data as Map));
  }

  /// Replace an entire `[[section]]` array-of-tables.
  ///
  /// Field-level patching cannot express a list: removing the second of three
  /// channels is not a change to any one key. Core replaces the block whole and
  /// leaves every other section alone, so the caller must send the full list —
  /// including the rows it did not touch.
  Future<ConfigSaveResult> putArrayOfTables(
    String section,
    List<Map<String, dynamic>> items,
  ) async {
    final res = await client.dio.put('/system/config', data: {
      'array_of_tables': {'section': section, 'items': items},
    });
    return ConfigSaveResult.fromJson(
        Map<String, dynamic>.from(res.data as Map));
  }

  /// Replace the file wholesale — the raw editor's save.
  Future<ConfigSaveResult> putRaw(String raw) async {
    final res = await client.dio.put('/system/config', data: {'raw': raw});
    return ConfigSaveResult.fromJson(
        Map<String, dynamic>.from(res.data as Map));
  }

  /// Ask core to restart itself. It answers before going down, so the caller
  /// should expect the connection to drop immediately afterwards.
  Future<void> restart() async {
    await client.dio.post(
      '/system/restart',
      options: Options(receiveTimeout: const Duration(seconds: 3)),
    );
  }

  /// Is core answering again? Used to poll through a restart.
  Future<bool> isUp() async {
    try {
      final res = await client.dio.get(
        '/system/status',
        options: Options(receiveTimeout: const Duration(seconds: 2)),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
