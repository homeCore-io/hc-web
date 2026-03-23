import 'homecore_client.dart';

class UsersApi {
  final HomecoreClient client;
  UsersApi(this.client);

  Future<List<Map<String, dynamic>>> listUsers() async {
    final response = await client.dio.get('/auth/users');
    return List<Map<String, dynamic>>.from(response.data as List);
  }

  Future<Map<String, dynamic>> createUser(
      String username, String password, String role) async {
    final response = await client.dio.post('/auth/users', data: {
      'username': username,
      'password': password,
      'role': role,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteUser(String id) async {
    await client.dio.delete('/auth/users/$id');
  }

  Future<Map<String, dynamic>> setRole(String id, String role) async {
    final response =
        await client.dio.patch('/auth/users/$id/role', data: {'role': role});
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> me() async {
    final response = await client.dio.get('/auth/me');
    return Map<String, dynamic>.from(response.data as Map);
  }
}
