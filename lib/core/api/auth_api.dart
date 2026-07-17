import 'homecore_client.dart';

class AuthApi {
  final HomecoreClient client;
  AuthApi(this.client);

  Future<String> login(String username, String password) async {
    final response = await client.dio.post('/auth/login', data: {
      'username': username,
      'password': password,
    });
    final token = response.data['token'] as String;
    final refresh = response.data['refresh_token'] as String?;
    // Store the refresh token too, so the session survives access-token expiry
    // without a re-login (silent renewal in HomecoreClient).
    await client.saveTokens(token, refresh);
    return token;
  }

  Future<void> logout() => client.clearToken();
}
