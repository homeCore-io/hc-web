class UserEntry {
  final String id;
  final String username;
  final String role;
  final String createdAt;

  UserEntry({
    required this.id,
    required this.username,
    required this.role,
    required this.createdAt,
  });

  factory UserEntry.fromJson(Map<String, dynamic> json) => UserEntry(
        id: json['id'] as String,
        username: json['username'] as String,
        role: json['role'] as String? ?? 'user',
        createdAt: json['created_at'] as String? ?? '',
      );

  String get displayRole => switch (role) {
        'admin' => 'Admin',
        'user' => 'User',
        'read_only' => 'Read Only',
        _ => role,
      };
}
