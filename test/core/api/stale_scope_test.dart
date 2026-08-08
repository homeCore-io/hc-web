import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/homecore_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Healing a 403 that is really a stale token.
///
/// Scopes are frozen into the access token at login. A release that adds one
/// leaves every existing session refused by a role that plainly grants it —
/// `skins:write` in 0.1.30, where Duplicate returned 403 from an admin account.
/// The client already refreshed silently on 401, but a 403 is not a 401, so
/// nothing reached that path and the only cure was signing out.
///
/// Core now derives scopes from the role at request time, so this condition
/// should not arise again from that cause. This is the other half: a client
/// upgraded ahead of its core, or any future claim that goes stale, heals
/// itself on one refresh instead of stranding the session.
///
/// **The important half is the second group.** A retry loop on a genuine
/// permission denial would be worse than the denial.

/// Serves scripted responses and records what was asked.
class _Fake implements HttpClientAdapter {
  _Fake(this.handle);

  /// (path, attempt) -> status. Attempt is 1-based per path.
  final int Function(String path, int attempt) handle;

  final List<String> calls = [];
  final Map<String, int> _attempts = {};

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<List<int>>? _, Future<void>? __) async {
    final path = options.path;
    calls.add(path);
    final n = (_attempts[path] ?? 0) + 1;
    _attempts[path] = n;
    final status = handle(path, n);
    final body = path.contains('/auth/refresh')
        ? jsonEncode({'token': 'fresh', 'refresh_token': 'fresh-refresh'})
        : jsonEncode({'ok': true});
    return ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

HomecoreClient _client(_Fake fake) {
  final c = HomecoreClient(baseUrl: 'http://localhost/api/v1');
  c.dio.httpClientAdapter = fake;
  // The refresh call goes out on its own Dio so it cannot recurse through the
  // interceptor; it needs the same fake or it would try the network.
  c.refreshDioForTest.httpClientAdapter = fake;
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
        'flutter.jwt_token': 'stale',
        'flutter.refresh_token': 'stale-refresh',
      }));

  group('a 403 that a refresh cures', () {
    test('refreshes once and replays the request', () async {
      // First attempt refused, second — after the refresh — allowed. This is
      // the shape of a token minted before the scope existed.
      final fake = _Fake((path, attempt) {
        if (path.contains('/auth/refresh')) return 200;
        return attempt == 1 ? 403 : 201;
      });
      final client = _client(fake);

      final res = await client.dio.post('/skins', data: {'id': 'x'});

      expect(res.statusCode, 201);
      expect(fake.calls, ['/skins', '/auth/refresh', '/skins'],
          reason: 'one refresh between the refusal and the replay');
    });

    test('the replay carries the refreshed token', () async {
      final fake = _Fake((path, attempt) {
        if (path.contains('/auth/refresh')) return 200;
        return attempt == 1 ? 403 : 200;
      });
      final client = _client(fake);
      await client.dio.get('/skins');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), 'fresh',
          reason: 'the refresh must have been stored before the replay');
    });
  });

  group('a 403 that is a real answer', () {
    test('is not retried forever, and does not sign you out', () async {
      // Refused before and after the refresh: a genuine "you may not".
      final fake = _Fake((path, attempt) {
        if (path.contains('/auth/refresh')) return 200;
        return 403;
      });
      final client = _client(fake);
      var loggedOut = false;
      client.onUnauthorized = () => loggedOut = true;

      await expectLater(
          client.dio.get('/admin/users'), throwsA(isA<DioException>()));

      expect(fake.calls.where((c) => c == '/admin/users').length, 2,
          reason: 'one retry, not a loop');
      expect(loggedOut, isFalse,
          reason: 'a permissions refusal is an answer, not an expired session '
              '— signing someone out for asking would be worse than the '
              'refusal');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), isNotNull,
          reason: 'the session survives a refusal');
    });

    test('a failed refresh leaves the 403 standing, still without logout',
        () async {
      final fake = _Fake((path, attempt) {
        if (path.contains('/auth/refresh')) return 401;
        return 403;
      });
      final client = _client(fake);
      var loggedOut = false;
      client.onUnauthorized = () => loggedOut = true;

      await expectLater(client.dio.get('/skins'), throwsA(isA<DioException>()));
      expect(loggedOut, isFalse);
    });

    test('with no token at all there is nothing to refresh', () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _Fake((path, attempt) => 403);
      final client = _client(fake);

      await expectLater(client.dio.get('/skins'), throwsA(isA<DioException>()));
      expect(fake.calls, ['/skins'],
          reason: 'no token, so no refresh was attempted');
    });
  });

  group('401 still behaves as it did', () {
    test('a refresh that works replays, and one that fails signs you out',
        () async {
      final fake = _Fake((path, attempt) {
        if (path.contains('/auth/refresh')) return 401;
        return 401;
      });
      final client = _client(fake);
      var loggedOut = false;
      client.onUnauthorized = () => loggedOut = true;

      await expectLater(
          client.dio.get('/devices'), throwsA(isA<DioException>()));
      expect(loggedOut, isTrue, reason: 'an expired session does end');
    });
  });
}
