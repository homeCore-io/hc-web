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

  /// Change *your own* password, proving you know the current one.
  ///
  /// Core takes the account from the token, not from an argument — there is no
  /// way to aim this at anybody else, which is why it is the one password call
  /// a non-admin can make.
  Future<void> changeOwnPassword(
      String currentPassword, String newPassword) async {
    await client.dio.post('/auth/change-password', data: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  /// Set another user's password. Admin only, and no current password.
  ///
  /// The way back in for someone who has forgotten theirs: a user record holds
  /// no email, so there is no reset-link flow to fall back on.
  Future<void> setPassword(String id, String newPassword) async {
    await client.dio.patch('/auth/users/$id/password', data: {
      'new_password': newPassword,
    });
  }

  Future<Map<String, dynamic>> me() async {
    final response = await client.dio.get('/auth/me');
    return Map<String, dynamic>.from(response.data as Map);
  }
}
