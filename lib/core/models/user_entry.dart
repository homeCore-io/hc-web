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
        'observer' => 'Observer',
        'device_operator' => 'Device Operator',
        'rule_editor' => 'Rule Editor',
        'service_operator' => 'Service Operator',
        _ => role,
      };

  /// The 7 roles the backend defines, in decreasing privilege — the full ladder
  /// the picker offers, not the 3 the UI once hardcoded.
  static const roles = <String>[
    'admin',
    'user',
    'read_only',
    'observer',
    'device_operator',
    'rule_editor',
    'service_operator',
  ];

  static String displayRoleOf(String role) => switch (role) {
        'admin' => 'Admin',
        'user' => 'User',
        'read_only' => 'Read Only',
        'observer' => 'Observer',
        'device_operator' => 'Device Operator',
        'rule_editor' => 'Rule Editor',
        'service_operator' => 'Service Operator',
        _ => role,
      };
}
