import 'homecore_client.dart';

/// An access key as the server lists it — metadata only, never the secret.
/// Mirrors the backend `ApiKeySummary`.
class ApiKeySummary {
  ApiKeySummary({
    required this.id,
    required this.label,
    required this.prefix,
    required this.ownerUid,
    required this.scopes,
    required this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
    this.allowedCidrs = const [],
    this.revokedAt,
  });

  final String id;
  final String label;

  /// First chars of the token body, for display as `hc_sk_<prefix>…`.
  final String prefix;
  final String ownerUid;
  final List<String> scopes;
  final String createdAt;
  final String? lastUsedAt;
  final String? expiresAt;
  final List<String> allowedCidrs;
  final String? revokedAt;

  bool get isRevoked => revokedAt != null;

  factory ApiKeySummary.fromJson(Map<String, dynamic> j) => ApiKeySummary(
        id: '${j['id']}',
        label: j['label'] as String? ?? '',
        prefix: j['prefix'] as String? ?? '',
        ownerUid: '${j['owner_uid']}',
        scopes: List<String>.from(j['scopes'] as List? ?? const []),
        createdAt: j['created_at'] as String? ?? '',
        lastUsedAt: j['last_used_at'] as String?,
        expiresAt: j['expires_at'] as String?,
        allowedCidrs:
            List<String>.from(j['allowed_cidrs'] as List? ?? const []),
        revokedAt: j['revoked_at'] as String?,
      );
}

/// The response from creating or rotating a key — the ONLY time the plaintext
/// `token` is returned. It must be shown once and never stored.
class CreatedApiKey {
  CreatedApiKey({required this.id, required this.label, required this.token});
  final String id;
  final String label;
  final String token;

  factory CreatedApiKey.fromJson(Map<String, dynamic> j) => CreatedApiKey(
        id: '${j['id']}',
        label: j['label'] as String? ?? '',
        token: j['token'] as String? ?? '',
      );
}

class ApiKeysApi {
  final HomecoreClient client;
  ApiKeysApi(this.client);

  Future<List<ApiKeySummary>> list() async {
    final response = await client.dio.get('/auth/api-keys');
    final items = (response.data as List? ?? const []);
    return items
        .whereType<Map>()
        .map((m) => ApiKeySummary.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Create a key. The returned `token` is shown once, then unrecoverable.
  Future<CreatedApiKey> create({
    required String label,
    required List<String> scopes,
    int? expiresInDays,
    List<String> allowedCidrs = const [],
    String? ownerUid,
  }) async {
    final response = await client.dio.post('/auth/api-keys', data: {
      'label': label,
      'scopes': scopes,
      if (expiresInDays != null) 'expires_in_days': expiresInDays,
      'allowed_cidrs': allowedCidrs,
      if (ownerUid != null) 'owner_uid': ownerUid,
    });
    return CreatedApiKey.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }

  Future<void> revoke(String id) async {
    await client.dio.delete('/auth/api-keys/$id');
  }

  /// Rotate a key: same metadata, new secret. Returns the new plaintext once.
  Future<CreatedApiKey> rotate(String id) async {
    final response = await client.dio.post('/auth/api-keys/$id/rotate');
    return CreatedApiKey.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }
}
