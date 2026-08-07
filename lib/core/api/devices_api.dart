import 'package:flutter/foundation.dart';

import 'homecore_client.dart';

class DevicesApi {
  late final HomecoreClient client;
  DevicesApi(this.client);

  /// For fakes that override the methods they need and never reach the wire.
  ///
  /// Same reasoning as [PluginsApi.fake]: [HomecoreClient] cannot be built
  /// under the Dart VM at all — dio rejects its relative `/api/v1` base URL off
  /// web — so a test double has no real client to pass up. Leaving [client]
  /// uninitialised is deliberate: a fake that falls through to a method it
  /// forgot to override should fail loudly rather than quietly try a request.
  @visibleForTesting
  DevicesApi.fake();

  /// Inlining the schemas costs one request instead of N, and the payload only
  /// grows for the devices that actually have one — 9 of 168 on a real install.
  Future<List<Map<String, dynamic>>> listDevices({
    bool includeSchema = true,
  }) async {
    final response = await client.dio.get(
      '/devices',
      queryParameters: includeSchema ? {'include_schema': true} : null,
    );
    return List<Map<String, dynamic>>.from(response.data as List);
  }

  Future<Map<String, dynamic>> getDevice(String id) async {
    final response = await client.dio.get('/devices/$id');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> setDeviceState(String id, Map<String, dynamic> state) async {
    await client.dio.patch('/devices/$id/state', data: state);
  }

  Future<Map<String, dynamic>> updateDevice(
      String id, Map<String, dynamic> body) async {
    final response = await client.dio.patch('/devices/$id', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteDevice(String id) async {
    await client.dio.delete('/devices/$id');
  }
}
