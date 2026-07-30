import 'dart:typed_data';

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

/// Core's live log filter: `GET`/`PUT /system/log-level`.
///
/// Separate from [SystemConfigApi] because it does not touch homecore.toml at
/// all. Core reloads the tracing filter in place and writes nothing, so the
/// setting is **runtime only** and a restart returns to `[logging] level` in
/// the file. Nothing in the response says so, so the screen has to.
class SystemLogLevelApi {
  SystemLogLevelApi(this.client);
  final HomecoreClient client;

  /// The active directive, or null when this core has no reloadable filter.
  ///
  /// Core answers 503 for that — a real state, not an error: the process is
  /// healthy, the knob simply is not there, and the screen should say so
  /// rather than show a control that cannot work.
  Future<String?> get() async {
    try {
      final res = await client.dio.get('/system/log-level');
      final data = Map<String, dynamic>.from(res.data as Map);
      return data['level'] as String?;
    } on DioException catch (e) {
      if (e.response?.statusCode == 503) return null;
      rethrow;
    }
  }

  /// Apply [directive].
  ///
  /// Core parses it as an EnvFilter and answers 400 with the parse error when
  /// it will not — that message names the part it choked on, which is the
  /// whole value of showing it, so it comes back rather than throwing.
  Future<({bool ok, String detail})> set(String directive) async {
    try {
      await client.dio.put('/system/log-level', data: {'level': directive});
      return (ok: true, detail: 'Applied.');
    } on DioException catch (e) {
      final data = e.response?.data;
      final detail = data is Map && data['error'] != null
          ? '${data['error']}'
          : (e.message ?? 'Unknown error');
      return (ok: false, detail: detail);
    }
  }
}

/// Backup, restore and calendars — the file-shaped half of Administration.
///
/// Separate from [SystemConfigApi] because none of it touches homecore.toml:
/// a backup is a zip of the databases, and a calendar is fetched from a URL
/// into core's own store.
class SystemDataApi {
  SystemDataApi(this.client);
  final HomecoreClient client;

  /// The whole house as a zip: both databases, the config, the rules.
  ///
  /// Returned as bytes rather than a URL because the endpoint is
  /// authenticated — a plain link would arrive without the token.
  Future<(String, Uint8List)> backup() async {
    final res = await client.dio.post<List<int>>(
      '/system/backup',
      options: Options(
        responseType: ResponseType.bytes,
        // A quarter-gigabyte zip is built and streamed; the default 10s
        // receive timeout cuts it off partway and looks like a server fault.
        receiveTimeout: const Duration(minutes: 10),
      ),
    );
    final disposition = res.headers.value('content-disposition') ?? '';
    final match = RegExp('filename="?([^";]+)').firstMatch(disposition);
    final name = match?.group(1) ?? 'homecore-backup.zip';
    return (name, Uint8List.fromList(res.data ?? const []));
  }

  /// Replace everything from a backup. Core answers with what it restored.
  Future<Map<String, dynamic>> restore(Uint8List zip) async {
    final res = await client.dio.post(
      '/system/restore',
      data: Stream.fromIterable([zip]),
      options: Options(
        headers: {
          'content-type': 'application/zip',
          'content-length': zip.length,
        },
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(minutes: 10),
      ),
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Send a message through a channel, so a person can find out whether it
  /// works without waiting for a rule to fire.
  ///
  /// Returns core's own words on failure: a channel that is not configured and
  /// an SMTP server that refused the credentials are different problems, and
  /// the message is the whole reason to press the button.
  Future<({bool sent, String detail})> testNotifyChannel(String channel) async {
    try {
      final res = await client.dio.post('/notify/test', data: {
        'channel': channel,
      });
      final body = Map<String, dynamic>.from(res.data as Map);
      return (sent: body['sent'] == true, detail: 'Sent.');
    } on DioException catch (e) {
      final data = e.response?.data;
      final detail = data is Map && data['error'] != null
          ? '${data['error']}'
          : (e.message ?? 'Unknown error');
      return (sent: false, detail: detail);
    }
  }

  Future<List<Map<String, dynamic>>> calendars() async {
    final res = await client.dio.get('/calendars');
    return [
      for (final c in (res.data as List)) Map<String, dynamic>.from(c as Map),
    ];
  }

  Future<void> addCalendar({
    required String url,
    String? name,
    int? refreshHours,
  }) async {
    await client.dio.post('/calendars/fetch', data: {
      'url': url,
      if (name != null && name.isNotEmpty) 'name': name,
      if (refreshHours != null) 'refresh_hours': refreshHours,
    });
  }

  Future<void> deleteCalendar(String id) async {
    await client.dio.delete('/calendars/$id');
  }
}
