import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomecoreClient {
  static const _tokenKey = 'jwt_token';
  static const _refreshKey = 'refresh_token';
  late final Dio dio;

  /// Bare client used only for the /auth/refresh call — it has no auth
  /// interceptor, so refreshing can't recurse back through [onError].
  late final Dio _refreshDio;

  /// In-flight refresh, shared by concurrent 401s so a burst of expired
  /// requests triggers exactly one /auth/refresh rather than a stampede.
  Future<bool>? _refreshing;

  /// Called when a request 401s AND a token refresh could not recover it — i.e.
  /// the session is truly over. Set by [AuthNotifier] to trigger logout.
  void Function()? onUnauthorized;

  /// Called for every non-401 error response. Set by [homecoreClientProvider]
  /// to feed the in-app client error log.
  void Function(int? statusCode, String method, String url, String body)?
      onApiError;

  /// [baseUrl] is relative on purpose: one build artifact runs anywhere, with
  /// the API served same-origin by nginx in production and by `tool/dev.mjs` in
  /// development. Dio only permits a relative base on the web, though, so a VM
  /// test cannot construct this at all without overriding it — which is part of
  /// why `lib/app.dart` had no test.
  HomecoreClient({String baseUrl = '/api/v1'}) {
    final opts = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    );
    dio = Dio(opts);
    _refreshDio = Dio(opts);

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString(_tokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final ro = error.requestOptions;
        final is401 = error.response?.statusCode == 401;
        final isAuthPath = ro.path.contains('/auth/');
        final alreadyRetried = ro.extra['__retried'] == true;

        // A 401 on a normal request: attempt one silent refresh, then replay
        // the original request. Only if the refresh itself fails do we log out.
        // This is the "remember me" behaviour — a session lives as long as the
        // 30-day refresh token, with access-token renewal that never interrupts
        // the user.
        if (is401 && !isAuthPath && !alreadyRetried) {
          if (await _refreshOnce()) {
            try {
              ro.extra['__retried'] = true;
              return handler.resolve(await dio.fetch(ro));
            } catch (_) {
              // Retry failed — fall through to logout.
            }
          }
          await clearToken();
          onUnauthorized?.call();
          return handler.next(error);
        }

        if (!is401) {
          final body = error.response?.data?.toString() ?? error.message ?? '';
          onApiError?.call(
              error.response?.statusCode, ro.method, ro.path, body);
        }
        handler.next(error);
      },
    ));
  }

  /// Refresh the access token, collapsing concurrent callers onto one request.
  Future<bool> _refreshOnce() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final rt = prefs.getString(_refreshKey);
    if (rt == null) return false;
    try {
      final res =
          await _refreshDio.post('/auth/refresh', data: {'refresh_token': rt});
      final access = res.data['token'] as String?;
      // Refresh tokens rotate (single-use), so store the new one it returns.
      final refresh = res.data['refresh_token'] as String?;
      if (access == null) return false;
      await saveTokens(access, refresh);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Store the access token and (if present) the rotated refresh token.
  Future<void> saveTokens(String access, String? refresh) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, access);
    if (refresh != null) await prefs.setString(_refreshKey, refresh);
  }

  /// Back-compat: store just the access token.
  Future<void> saveToken(String token) => saveTokens(token, null);

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshKey);
  }

  Future<bool> hasToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey) != null;
  }
}
