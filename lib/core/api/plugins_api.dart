import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/plugin_config.dart';
import '../models/registry_plugin.dart';
import '../schema/plugin_capabilities.dart';
import 'homecore_client.dart';

/// The result of invoking a plugin action.
sealed class CommandOutcome {
  const CommandOutcome();
}

/// A non-streaming action that returned a value.
class CommandDone extends CommandOutcome {
  const CommandDone(this.data);
  final Object? data;
}

/// A streaming action. Follow it with `openActionStream(requestId: ...)`.
class CommandStreaming extends CommandOutcome {
  const CommandStreaming(this.requestId);
  final String requestId;
}

/// A `concurrency: "single"` action that is already running.
///
/// Core answers 409 with the *active* request id, which means the honest UI move
/// is to attach to the run in progress rather than to report an error — starting
/// a second Z-Wave inclusion is not something the user wanted.
class CommandBusy extends CommandOutcome {
  const CommandBusy(this.activeRequestId);
  final String activeRequestId;
}

class PluginsApi {
  late final HomecoreClient client;
  PluginsApi(this.client);

  /// For fakes that override the methods they need and never reach the wire.
  ///
  /// [HomecoreClient] cannot be built under the Dart VM at all — dio rejects
  /// its relative `/api/v1` base URL off-web — so a test double has no real
  /// client to pass up. Leaving [client] uninitialised is deliberate: a fake
  /// that falls through to an un-overridden method should fail loudly rather
  /// than quietly attempt a request.
  @visibleForTesting
  PluginsApi.fake();

  Future<List<Map<String, dynamic>>> listPlugins() async {
    final response = await client.dio.get('/plugins');
    return List<Map<String, dynamic>>.from(response.data as List);
  }

  /// The volatile subset of the plugin list — core 0.1.16 and later.
  ///
  /// Same records minus `capabilities`, `config_schema` and
  /// `config_descriptor`, which never change and each have their own endpoint.
  /// On an 11-plugin house that is 5 KB instead of 127 KB.
  Future<List<Map<String, dynamic>>> listPluginStatus() async {
    final response = await client.dio.get('/plugins/status');
    return List<Map<String, dynamic>>.from(response.data as List);
  }

  /// null until probed, then true/false for the life of this client.
  bool? _slimSupported;

  /// The list as a live view should fetch it: slim where core offers it.
  ///
  /// [PluginEntry] reads none of the heavy fields, so nothing is lost by
  /// preferring the slim route. An older core answers 404, and we fall back
  /// **permanently** rather than per-call: this is polled every few seconds,
  /// and a fallback that re-probed would spend a 404 on every tick forever.
  Future<List<Map<String, dynamic>>> listPluginsLive() async {
    if (_slimSupported != false) {
      try {
        final rows = await listPluginStatus();
        _slimSupported = true;
        return rows;
      } on DioException catch (e) {
        // Only a missing route means "old core". Anything else — 401, 500, a
        // dropped connection — is a real failure and must not be papered over
        // by silently asking a different endpoint.
        if (e.response?.statusCode != 404) rethrow;
        _slimSupported = false;
      }
    }
    return listPlugins();
  }

  /// Uninstall a plugin.
  ///
  /// Core purges the config file and the installed binaries by default. Both
  /// used to survive an uninstall, so a reinstall silently adopted the removed
  /// plugin's host, credentials and device rows.
  ///
  /// [keepConfig] is for the case where reinstalling *is* the fix and the
  /// config is the part worth keeping. Binaries always go — they are a signed
  /// download and cost nothing to fetch again.
  Future<Map<String, dynamic>> deregister(String id,
      {bool keepConfig = false}) async {
    final response = await client.dio.delete(
      '/plugins/$id',
      queryParameters: keepConfig ? {'keep_config': true} : null,
    );
    final data = response.data;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// Browse the remote registry. 503 (no registry configured) surfaces as an
  /// empty list so the catalog can say "no registry" rather than error.
  Future<List<RegistryPlugin>> registryPlugins() async {
    final response = await client.dio.get('/registry/plugins');
    final list = (response.data['plugins'] as List?) ?? const [];
    return list.map((e) => RegistryPlugin.fromJson(e as Map)).toList();
  }

  /// Install a plugin from the registry; core resolves + downloads + verifies +
  /// installs + activates. Returns the install summary.
  /// Install from the registry. Core decides *where* it runs.
  ///
  /// [runtimeId] pins the choice to one plugin runtime, which is only needed
  /// when several could host it — core answers `409` with the candidates, and
  /// the caller repeats the request with one of them. Sending it when there is
  /// no ambiguity is harmless; sending a wrong one is refused rather than
  /// quietly redirected.
  Future<Map<String, dynamic>> installFromRegistry(String id,
      {String? version, String? runtimeId}) async {
    final response = await client.dio.post('/plugins/install', data: {
      'id': id,
      if (version != null) 'version': version,
      if (runtimeId != null) 'runtime_id': runtimeId,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// 404 when the plugin has never published a manifest — which is normal, and
  /// not an error worth surfacing. Several plugins publish none at all.
  Future<PluginCapabilities?> capabilities(String id) async {
    try {
      final response = await client.dio.get('/plugins/$id/capabilities');
      return PluginCapabilities.fromJson(response.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Invokes an action. Params are flattened alongside `action`, not nested.
  Future<CommandOutcome> invoke(
    String pluginId,
    PluginAction action,
    Map<String, Object?> params,
  ) async {
    try {
      final response = await client.dio.post(
        '/plugins/$pluginId/command',
        data: action.commandBody(params),
        // A streaming action's own work may take minutes (Z-Wave inclusion has
        // a 60s+ pairing window); the default 10s receive timeout would abort
        // the POST that merely *starts* it.
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      );

      final data = response.data;
      if (action.stream && data is Map && data['request_id'] != null) {
        return CommandStreaming('${data['request_id']}');
      }
      return CommandDone(data);
    } on DioException catch (e) {
      final body = e.response?.data;
      if (e.response?.statusCode == 409 &&
          body is Map &&
          body['active_request_id'] != null) {
        return CommandBusy('${body['active_request_id']}');
      }
      rethrow;
    }
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await client.dio.patch('/plugins/$id', data: {'enabled': enabled});
  }

  /// Ask a plugin to change its live log filter.
  ///
  /// Core records the value and fires a `set_log_level` management command at
  /// the plugin **without waiting for the answer** — the reply is dropped, so a
  /// 200 here means "asked", not "applied". A plugin with
  /// `supports_management == false` never receives it at all; callers should
  /// not offer this for one.
  ///
  /// Not persisted anywhere: `PATCH /plugins/:id` writes only `enabled` to
  /// homecore.toml. The plugin's own `logging.level` is the durable setting.
  Future<void> setLogLevel(String id, String directive) async {
    await client.dio.patch('/plugins/$id', data: {'log_level': directive});
  }

  Future<void> lifecycle(String id, String action) async {
    // action ∈ start | stop | restart
    await client.dio.post('/plugins/$id/$action');
  }

  /// The plugin's operator config (secrets redacted). 404 when the plugin has
  /// no config path and no management RPC — the UI then shows nothing to edit.
  Future<PluginConfigDoc?> getConfig(String id) async {
    try {
      final response = await client.dio.get('/plugins/$id/config');
      return PluginConfigDoc.fromJson(response.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Replace the config. Pass exactly one of [raw] (TOML text, written verbatim)
  /// or [config] (JSON, serialised to TOML by core). Redacted secrets left as
  /// `__redacted__` are restored to their stored value by core, so an untouched
  /// secret survives the round-trip. Does not restart the plugin.
  Future<void> putConfig(
    String id, {
    String? raw,
    Map<String, dynamic>? config,
  }) async {
    assert(
      (raw != null) ^ (config != null),
      'putConfig needs exactly one of raw or config',
    );
    await client.dio.put(
      '/plugins/$id/config',
      data: raw != null ? {'raw': raw} : {'config': config},
    );
  }

  /// The plugin's operator-config JSON Schema, or null when it published none
  /// (404) — in which case the editor falls back to the raw-TOML view.
  Future<Map<String, dynamic>?> configSchema(String id) async {
    try {
      final response = await client.dio.get('/plugins/$id/config/schema');
      final data = response.data as Map;
      final schema = data['schema'];
      return schema == null ? null : Map<String, dynamic>.from(schema as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// The plugin's own config *descriptor* (the richer, plugin-authored
  /// description of its configuration), or null when it publishes none — the
  /// client then falls back to a descriptor auto-derived from the schema.
  /// 404 today for every plugin until the SDK emits one.
  Future<Map<String, dynamic>?> configDescriptor(String id) async {
    try {
      final response = await client.dio.get('/plugins/$id/config/descriptor');
      final data = response.data as Map;
      final d = data['descriptor'] ?? data;
      return d == null ? null : Map<String, dynamic>.from(d as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}
