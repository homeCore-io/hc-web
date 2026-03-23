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
    await client.saveToken(token);
    return token;
  }

  Future<void> logout() => client.clearToken();
}
