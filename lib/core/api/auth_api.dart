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

  /// Every role and the scopes it grants, from `GET /auth/roles`. Used to show
  /// what a role can do and to bound an access key's scopes to its owner's.
  Future<List<RoleInfo>> roles() async {
    final response = await client.dio.get('/auth/roles');
    final items = (response.data as List? ?? const []);
    return items
        .whereType<Map>()
        .map((m) => RoleInfo.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }
}

/// A role and the scopes it grants — the client-side view of the backend's
/// `Role::scopes()`, fetched rather than duplicated.
class RoleInfo {
  RoleInfo({required this.role, required this.scopes});
  final String role;
  final List<String> scopes;

  /// `device_operator` → "Device Operator".
  String get label => role
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  factory RoleInfo.fromJson(Map<String, dynamic> j) => RoleInfo(
        role: j['role'] as String? ?? '',
        scopes: List<String>.from(j['scopes'] as List? ?? const []),
      );
}
