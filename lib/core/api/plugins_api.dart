import 'package:dio/dio.dart';

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
  final HomecoreClient client;
  PluginsApi(this.client);

  Future<List<Map<String, dynamic>>> listPlugins() async {
    final response = await client.dio.get('/plugins');
    return List<Map<String, dynamic>>.from(response.data as List);
  }

  Future<void> deregister(String id) async {
    await client.dio.delete('/plugins/$id');
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
  Future<Map<String, dynamic>> installFromRegistry(String id,
      {String? version}) async {
    final response = await client.dio.post('/plugins/install', data: {
      'id': id,
      if (version != null) 'version': version,
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
}
