import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomecoreClient {
  static const _tokenKey = 'jwt_token';
  late final Dio dio;

  /// Called when any request receives a 401. Set by [AuthNotifier] to trigger
  /// a logout/redirect without requiring Riverpod access here.
  void Function()? onUnauthorized;

  /// Called for every non-401 error response. Set by [homecoreClientProvider]
  /// to feed the in-app client error log.
  void Function(int? statusCode, String method, String url, String body)?
      onApiError;

  HomecoreClient() {
    dio = Dio(BaseOptions(
      baseUrl: '/api/v1',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));

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
        if (error.response?.statusCode == 401) {
          await clearToken();
          onUnauthorized?.call();
        } else {
          final body = error.response?.data?.toString() ?? error.message ?? '';
          onApiError?.call(
            error.response?.statusCode,
            error.requestOptions.method,
            error.requestOptions.path,
            body,
          );
        }
        handler.next(error);
      },
    ));
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<bool> hasToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey) != null;
  }
}
