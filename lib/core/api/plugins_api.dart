import 'package:dio/dio.dart';

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
}
