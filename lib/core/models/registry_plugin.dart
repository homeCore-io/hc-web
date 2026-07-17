/// One plugin as listed in the remote registry index (`GET /registry/plugins`).
class RegistryPlugin {
  const RegistryPlugin({
    required this.id,
    this.name = '',
    this.description = '',
    this.category = '',
    this.versions = const [],
  });

  final String id;
  final String name;
  final String description;
  final String category;

  /// Version strings, oldest → newest (the registry publishes in order).
  final List<String> versions;

  String get displayName => name.isNotEmpty ? name : id;
  String? get latest => versions.isEmpty ? null : versions.last;

  factory RegistryPlugin.fromJson(Map json) => RegistryPlugin(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        category: (json['category'] ?? '').toString(),
        versions: ((json['versions'] as List?) ?? const [])
            .map((v) => (v is Map ? (v['version'] ?? '') : '').toString())
            .where((s) => s.isNotEmpty)
            .toList(),
      );
}
