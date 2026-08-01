import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/plugins_api.dart';

DioException _http(int code) => DioException(
      requestOptions: RequestOptions(path: '/plugins/status'),
      response: Response(
          requestOptions: RequestOptions(path: '/plugins/status'),
          statusCode: code),
    );

/// Counts which route was taken, and can make either one fail.
class _Api extends PluginsApi {
  _Api() : super.fake();

  int slimCalls = 0;
  int fatCalls = 0;
  Object? slimThrows;

  @override
  Future<List<Map<String, dynamic>>> listPluginStatus() async {
    slimCalls++;
    if (slimThrows case final e?) throw e;
    return [
      {'plugin_id': 'plugin.ecowitt', 'device_count': 9}
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> listPlugins() async {
    fatCalls++;
    return [
      {'plugin_id': 'plugin.ecowitt', 'device_count': 9, 'capabilities': {}}
    ];
  }
}

void main() {
  group('listPluginsLive', () {
    test('uses the slim route when core has it', () async {
      final api = _Api();
      final rows = await api.listPluginsLive();
      expect(rows.single['device_count'], 9);
      expect(api.slimCalls, 1);
      expect(api.fatCalls, 0);
    });

    test('a 404 falls back once and never probes again', () async {
      // The point: this runs on a 10s poll. Re-probing would burn a 404 per
      // tick, forever, against every core older than 0.1.16.
      final api = _Api()..slimThrows = _http(404);
      await api.listPluginsLive();
      await api.listPluginsLive();
      await api.listPluginsLive();

      expect(api.slimCalls, 1, reason: 'probed exactly once');
      expect(api.fatCalls, 3);
    });

    test('a real failure propagates rather than silently changing route',
        () async {
      final api = _Api()..slimThrows = _http(401);
      await expectLater(api.listPluginsLive(), throwsA(isA<DioException>()));
      expect(api.fatCalls, 0, reason: '401 is not "this core is old"');
    });

    test('a transient 500 does not condemn the slim route', () async {
      final api = _Api()..slimThrows = _http(500);
      await expectLater(api.listPluginsLive(), throwsA(isA<DioException>()));

      api.slimThrows = null;
      final rows = await api.listPluginsLive();
      expect(rows.single['device_count'], 9);
      expect(api.fatCalls, 0);
    });
  });
}
