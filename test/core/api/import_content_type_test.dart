import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The import endpoints post a top-level JSON array, and that is the one shape
/// dio does *not* infer a content type for.
///
/// `ImplyContentTypeInterceptor` sets `application/json` for `Map`, `String`
/// and `List<Map>`. `jsonDecode` of an export returns `List<dynamic>`, and
/// `List<dynamic> is List<Map>` is false — so dio logged a warning, sent the
/// body with no Content-Type at all, and axum's `Json` extractor rejected it
/// with 415 before the handler ran. The symptom was an import that failed with
/// what looked like a server fault.
void main() {
  late HttpServer server;
  late List<String?> received;

  setUp(() async {
    received = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      received.add(req.headers.contentType?.mimeType);
      await req.drain<void>();
      req.response
        ..statusCode = 201
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'imported': 0}));
      await req.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  Dio client() => Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}'));

  test('a bare List<dynamic> gets no content type from dio on its own',
      () async {
    // Not a wish — a guard. If dio ever starts inferring this, the explicit
    // option below becomes redundant rather than load-bearing, and whoever
    // sees this fail should delete the option, not work around it.
    final rules = jsonDecode('[{"id":"a"},{"id":"b"}]') as List<dynamic>;
    await client().post('/automations/import', data: rules);
    expect(received.single, isNot('application/json'),
        reason: 'dio inferred a JSON content type unaided');
  });

  test('stating it explicitly is what makes the import reach the handler',
      () async {
    final rules = jsonDecode('[{"id":"a"},{"id":"b"}]') as List<dynamic>;
    await client().post('/automations/import',
        data: rules, options: Options(contentType: Headers.jsonContentType));
    expect(received.single, 'application/json');
  });

  test('the body still arrives as a JSON array, not a stringified one',
      () async {
    late String raw;
    final echo = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    echo.listen((req) async {
      raw = await utf8.decoder.bind(req).join();
      req.response.statusCode = 201;
      req.response.headers.contentType = ContentType.json;
      req.response.write('{}');
      await req.response.close();
    });
    addTearDown(() => echo.close(force: true));

    final rules = jsonDecode('[{"id":"a"}]') as List<dynamic>;
    await Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${echo.port}')).post(
        '/automations/import',
        data: rules,
        options: Options(contentType: Headers.jsonContentType));
    expect(jsonDecode(raw), isA<List<dynamic>>());
  });
}
