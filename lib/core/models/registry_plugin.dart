/// What one published build runs on.
///
/// `runtime` is `native` for a static binary core unpacks and runs itself —
/// which is what every entry published before plugin runtimes existed means,
/// and why it defaults rather than being required. Anything else names a
/// runtime kind (`python`) and carries the `abi` its host must match.
class RegistryArtifact {
  const RegistryArtifact({
    this.os = '',
    this.arch = '',
    this.runtime = 'native',
    this.abi = '',
  });

  final String os;
  final String arch;
  final String runtime;
  final String abi;

  bool get isNative => runtime == 'native';

  /// How to say what this needs, to someone who has not enrolled one.
  String get requirement => '$runtime $abi on $arch';

  factory RegistryArtifact.fromJson(Map json) => RegistryArtifact(
        os: (json['os'] ?? '').toString(),
        arch: (json['arch'] ?? '').toString(),
        runtime: (json['runtime'] ?? 'native').toString(),
        abi: (json['abi'] ?? '').toString(),
      );
}

/// One plugin as listed in the remote registry index (`GET /registry/plugins`).
class RegistryPlugin {
  const RegistryPlugin({
    required this.id,
    this.name = '',
    this.description = '',
    this.category = '',
    this.versions = const [],
    this.artifacts = const {},
  });

  final String id;
  final String name;
  final String description;
  final String category;

  /// Version strings, oldest → newest (the registry publishes in order).
  final List<String> versions;

  /// Artifacts per version, keyed by version string.
  ///
  /// Kept so the catalogue can say *where* a plugin would install before
  /// anyone clicks. Core decides placement — this never overrides it — but a
  /// row that offers Install and then fails with "no runtime can host this"
  /// has wasted the operator's time and told them nothing they could have
  /// known.
  final Map<String, List<RegistryArtifact>> artifacts;

  List<RegistryArtifact> artifactsFor(String? version) =>
      artifacts[version ?? latest] ?? const [];

  /// True when this version publishes nothing core can run by itself.
  bool needsRuntime(String? version) {
    final arts = artifactsFor(version);
    return arts.isNotEmpty && !arts.any((a) => a.isNative);
  }

  /// The runtime kinds this version publishes for, for a message that names
  /// what to go and enroll.
  List<RegistryArtifact> runtimeArtifacts(String? version) =>
      artifactsFor(version).where((a) => !a.isNative).toList();

  String get displayName => name.isNotEmpty ? name : id;

  /// The newest version the registry lists.
  ///
  /// By comparison, not by position: the index is published in order today,
  /// but "publishes in order" is a convention, and 0.1.10 sorts before 0.1.9
  /// the moment anyone compares these as strings.
  String? get latest {
    if (versions.isEmpty) return null;
    var best = versions.first;
    for (final v in versions.skip(1)) {
      if (compareVersions(v, best) > 0) best = v;
    }
    return best;
  }

  /// The version worth upgrading to, or null when [installed] is already it.
  ///
  /// Null for an unknown installed version too: "an update is available" is a
  /// claim, and we do not make it on a guess.
  String? updateFrom(String? installed) {
    final newest = latest;
    if (newest == null || installed == null || installed.isEmpty) return null;
    return compareVersions(newest, installed) > 0 ? newest : null;
  }

  /// Numeric-segment comparison — `0.1.10` is newer than `0.1.9`.
  ///
  /// Anything non-numeric compares as text so a suffix (`0.2.0-rc1`) is
  /// ordered rather than crashing; it is not a full semver implementation and
  /// does not pretend to be.
  static int compareVersions(String a, String b) {
    final x = a.split(RegExp(r'[.+-]'));
    final y = b.split(RegExp(r'[.+-]'));
    for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
      final l = i < x.length ? x[i] : null;
      final r = i < y.length ? y[i] : null;
      final ln = l == null ? null : int.tryParse(l);
      final rn = r == null ? null : int.tryParse(r);

      // One side ran out of segments. A *numeric* extra means more version
      // (0.2 < 0.2.1); a non-numeric one is a pre-release, and a pre-release
      // is older than the release it leads to (0.2.0-rc1 < 0.2.0).
      if (l == null) return rn != null ? -1 : 1;
      if (r == null) return ln != null ? 1 : -1;

      final c = (ln != null && rn != null) ? ln.compareTo(rn) : l.compareTo(r);
      if (c != 0) return c;
    }
    return 0;
  }

  factory RegistryPlugin.fromJson(Map json) => RegistryPlugin(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        category: (json['category'] ?? '').toString(),
        versions: ((json['versions'] as List?) ?? const [])
            .map((v) => (v is Map ? (v['version'] ?? '') : '').toString())
            .where((s) => s.isNotEmpty)
            .toList(),
        artifacts: {
          for (final v in ((json['versions'] as List?) ?? const []))
            if (v is Map && (v['version'] ?? '').toString().isNotEmpty)
              (v['version']).toString(): ((v['artifacts'] as List?) ?? const [])
                  .whereType<Map>()
                  .map(RegistryArtifact.fromJson)
                  .toList(),
        },
      );
}
