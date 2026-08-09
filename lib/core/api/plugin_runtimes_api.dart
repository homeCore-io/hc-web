import 'package:dio/dio.dart';

import 'homecore_client.dart';

/// A plugin runtime as the server lists it. Mirrors the backend
/// `RuntimeSummary`, which never carries the enrollment secret or the
/// credentials.
///
/// A runtime is a container the operator runs, hosting plugins written in
/// something other than Rust. Once approved it registers as an ordinary plugin
/// and is managed like one — so this type only exists for the moment *before*
/// that, when it is a stranger asking to join.
class PluginRuntimeSummary {
  PluginRuntimeSummary({
    required this.runtimeId,
    required this.status,
    required this.kind,
    required this.abi,
    required this.arch,
    required this.hostVersion,
    required this.sdkVersion,
    required this.hostname,
    required this.networkMode,
    required this.createdAt,
    this.code,
    this.sourceIp,
    this.lastSeenAt,
    this.pluginId,
    this.expiresAt,
  });

  final String runtimeId;

  /// `pending` | `approved` | `denied`.
  final String status;

  /// What it can host: `python`, and one day others.
  final String kind;

  /// ABI its artifacts must match, e.g. `cp312-manylinux_2_28`.
  final String abi;
  final String arch;
  final String hostVersion;
  final String sdkVersion;
  final String hostname;
  final String networkMode;
  final String createdAt;

  /// Short and human-comparable, shown only while pending.
  ///
  /// **Not a credential.** It exists so the operator can confirm *this*
  /// container against the code in its logs, rather than approving whatever
  /// happened to ask at the right moment. In open mode this comparison is the
  /// security, which is why the UI has to make it hard to skip.
  final String? code;

  /// Where the request came from. Part of the same judgement as the code.
  final String? sourceIp;
  final String? lastSeenAt;

  /// The plugin id it registers under once approved.
  final String? pluginId;

  /// When a pending record stops being answerable.
  final String? expiresAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';

  /// What it advertises it can run, as one line.
  String get capability => '$kind · $abi · $arch';

  factory PluginRuntimeSummary.fromJson(Map<String, dynamic> j) {
    final caps = Map<String, dynamic>.from(
        (j['capabilities'] as Map?) ?? const <String, dynamic>{});
    return PluginRuntimeSummary(
      runtimeId: '${j['runtime_id']}',
      status: j['status'] as String? ?? 'pending',
      kind: caps['kind'] as String? ?? '',
      abi: caps['abi'] as String? ?? '',
      arch: caps['arch'] as String? ?? '',
      hostVersion: j['host_version'] as String? ?? '',
      sdkVersion: j['sdk_version'] as String? ?? '',
      hostname: j['hostname'] as String? ?? '',
      networkMode: j['network_mode'] as String? ?? '',
      createdAt: j['created_at'] as String? ?? '',
      code: j['code'] as String?,
      sourceIp: j['source_ip'] as String?,
      lastSeenAt: j['last_seen_at'] as String?,
      pluginId: j['plugin_id'] as String?,
      expiresAt: j['expires_at'] as String?,
    );
  }
}

/// Where one plugin runs. The admin view of a placement — no config, because
/// that holds a minted broker credential and is edited through the plugin's own
/// config surface.
class PluginPlacement {
  PluginPlacement({
    required this.runtimeId,
    required this.pluginId,
    required this.version,
    this.placedAt,
  });

  final String runtimeId;
  final String pluginId;
  final String version;
  final String? placedAt;

  factory PluginPlacement.fromJson(Map<String, dynamic> j) => PluginPlacement(
        runtimeId: '${j['runtime_id']}',
        pluginId: '${j['plugin_id']}',
        version: j['version'] as String? ?? '',
        placedAt: j['placed_at'] as String?,
      );
}

/// A one-time enrollment token, shown once and never again.
class EnrollToken {
  EnrollToken({required this.token, this.expiresAt});
  final String token;
  final String? expiresAt;

  factory EnrollToken.fromJson(Map<String, dynamic> j) => EnrollToken(
        token: j['token'] as String? ?? '',
        expiresAt: j['expires_at'] as String?,
      );
}

class PluginRuntimesApi {
  final HomecoreClient client;
  PluginRuntimesApi(this.client);

  /// Every runtime, whatever its status.
  ///
  /// Returns an empty list when the feature is switched off: `[plugin_runtimes]
  /// enabled = false` makes the endpoints 404, and a deployment that will never
  /// host a runtime should see an empty section rather than an error about
  /// something it does not use.
  Future<List<PluginRuntimeSummary>> list() async {
    final response = await client.dio.get(
      '/plugin-runtimes',
      options: _tolerate404,
    );
    if (response.statusCode == 404) return const [];
    final body = Map<String, dynamic>.from(response.data as Map);
    return (body['runtimes'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => PluginRuntimeSummary.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Every plugin placed on a runtime, from the admin side.
  ///
  /// Answers both halves of the question in one request: what a runtime hosts,
  /// and where a given plugin runs. Empty when the feature is off, for the same
  /// reason [list] is.
  Future<List<PluginPlacement>> placements() async {
    final response = await client.dio.get(
      '/plugin-runtimes/placements',
      options: _tolerate404,
    );
    if (response.statusCode == 404) return const [];
    final body = Map<String, dynamic>.from(response.data as Map);
    return (body['placements'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => PluginPlacement.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<void> approve(String runtimeId) async {
    await client.dio
        .post('/plugin-runtimes/$runtimeId/approve', data: const {});
  }

  /// Deny a request. The runtime may try again — the common case is an operator
  /// who denied by accident, or one container while another was expected.
  Future<void> deny(String runtimeId, {String? reason}) async {
    await client.dio.post('/plugin-runtimes/$runtimeId/deny', data: {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  /// Mint a one-time enrollment token, for token mode or for automation.
  Future<EnrollToken> issueToken() async {
    final response =
        await client.dio.post('/plugin-runtimes/tokens', data: const {});
    return EnrollToken.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }
}

/// A 404 here means the feature is switched off, which is not an error worth
/// throwing — it is the documented answer for a deployment that will never host
/// a runtime, and `[plugin_runtimes] enabled = false` is meant to remove the
/// surface rather than forbid it.
final _tolerate404 = Options(
  validateStatus: (s) => s != null && (s < 400 || s == 404),
);
