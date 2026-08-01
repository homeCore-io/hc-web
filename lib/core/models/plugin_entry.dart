import '../text/humanize.dart';
import 'plugin_notice.dart';
import 'registry_plugin.dart';

/// A registered plugin, as returned by `GET /plugins` (a `PluginRecord`).
class PluginEntry {
  const PluginEntry({
    required this.pluginId,
    required this.status,
    required this.registeredAt,
    this.enabled = false,
    this.managed = false,
    this.deviceCount = 0,
    this.version,
    this.installedVersion,
    this.uptimeStarted,
    this.lastHeartbeat,
    this.configPath,
    this.supportsManagement = false,
    this.logLevel,
    this.notices = const [],
  });

  final String pluginId;

  /// "active" | "offline" | "stopped" | "starting" | "unknown".
  final String status;
  final String registeredAt;
  final bool enabled;

  /// Local child process (true) vs remote MQTT-only (false).
  final bool managed;
  final int deviceCount;

  /// Version the running process reports — what is actually executing.
  final String? version;

  /// Installed artifact version (registry/managed plugins), for "update available".
  ///
  /// Null for a plugin nobody installed: one declared straight in `homecore.toml`
  /// against a build path (hue in the sandbox) has no install record to keep, and
  /// so can never disagree with one.
  final String? installedVersion;
  final DateTime? uptimeStarted;
  final DateTime? lastHeartbeat;
  final String? configPath;
  final bool supportsManagement;

  /// The log filter core last *asked* this plugin for, and nothing more.
  ///
  /// Core records it when the request is sent and never hears back — the reply
  /// is dropped on the way — so this is intent, not confirmation. Null means
  /// nobody has asked during this run of core: the plugin is on whatever
  /// `logging.level` in its own config said at boot. Core also forgets it when
  /// the plugin re-registers, which is what a plugin restart does.
  final String? logLevel;

  /// Conditions the plugin is currently reporting about itself.
  ///
  /// Empty for a plugin on an SDK without notices, which is the same shape as
  /// "nothing to report" — so no distinction is drawn between the two.
  final List<PluginNotice> notices;

  factory PluginEntry.fromJson(Map<String, dynamic> json) => PluginEntry(
        pluginId: json['plugin_id'] as String,
        status: json['status'] as String? ?? 'unknown',
        registeredAt: json['registered_at'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? false,
        managed: json['managed'] as bool? ?? false,
        deviceCount: (json['device_count'] as num?)?.toInt() ?? 0,
        version: json['version'] as String?,
        installedVersion: json['installed_version'] as String?,
        uptimeStarted: DateTime.tryParse('${json['uptime_started'] ?? ''}'),
        lastHeartbeat: DateTime.tryParse('${json['last_heartbeat'] ?? ''}'),
        configPath: json['config_path'] as String?,
        supportsManagement: json['supports_management'] as bool? ?? false,
        logLevel: json['log_level'] as String?,
        notices: (json['notices'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(PluginNotice.fromJson)
                .toList() ??
            const [],
      );

  PluginEntry copyWith({String? status, bool? enabled}) => PluginEntry(
        pluginId: pluginId,
        status: status ?? this.status,
        registeredAt: registeredAt,
        enabled: enabled ?? this.enabled,
        managed: managed,
        deviceCount: deviceCount,
        version: version,
        installedVersion: installedVersion,
        uptimeStarted: uptimeStarted,
        lastHeartbeat: lastHeartbeat,
        configPath: configPath,
        supportsManagement: supportsManagement,
        logLevel: logLevel,
        notices: notices,
      );

  /// Notices worth interrupting for — everything except `info`.
  ///
  /// Split out because "active with 0 devices and an error notice" is the state
  /// this whole mechanism exists to make visible, and it should not be buried
  /// among informational lines.
  List<PluginNotice> get problems => notices.where((n) => !n.isInfo).toList();

  bool get hasProblems => problems.isNotEmpty;

  bool get isActive => status == 'active';
  bool get isOffline => status == 'offline';
  bool get isStopped => status == 'stopped' || status == 'starting';

  /// Human display name: `plugin.hue` → "Hue", `plugin.zwave` → "Z Wave".
  String get displayName {
    final bare = pluginId.startsWith('plugin.')
        ? pluginId.substring('plugin.'.length)
        : pluginId;
    return humanize(bare);
  }

  /// Rough uptime string, e.g. "3h 12m". Null when not running.
  String? get uptime {
    final started = uptimeStarted;
    if (started == null || !isActive) return null;
    final d = DateTime.now().toUtc().difference(started);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inDays}d ${d.inHours % 24}h';
  }

  /// Compact "time since last heartbeat", e.g. "12s", "4m". Null if never seen.
  String? get heartbeatAgo {
    final h = lastHeartbeat;
    if (h == null) return null;
    final d = DateTime.now().toUtc().difference(h);
    if (d.inSeconds < 60) return '${d.inSeconds < 0 ? 0 : d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  /// The process is running a build other than the one the install record
  /// names — an upgrade that wrote the record but never restarted the child, a
  /// restart that came back on the old artifact, or a binary swapped underneath.
  ///
  /// Whatever the cause, the two disagree and only one of them is real: what
  /// [version] says is executing. Reporting the installed version alone hides
  /// that, and comparing the installed version against the registry answers a
  /// question about an artifact nobody is running.
  ///
  /// Needs both to be known — an unmanaged plugin has no record to differ from,
  /// and absence is not disagreement.
  bool get versionDiverged =>
      version != null &&
      installedVersion != null &&
      version != installedVersion;

  /// Whether [latest] from the registry is actually something to fetch.
  ///
  /// Not merely "differs from the install record". A plugin can already be
  /// *running* the version the registry offers while its record lags behind
  /// (see [versionDiverged]), and then "Update to v0.1.4" is a button that
  /// downloads what is already executing. What that plugin needs is its record
  /// reconciled, not an artifact.
  ///
  /// **Ordering, not merely inequality.** This used to be `latest !=
  /// installed && latest != running`, on the reasoning that versions are
  /// opaque strings here and guessing at precedence would be worse than
  /// asking. That reasoning stopped holding once
  /// [RegistryPlugin.compareVersions] existed — and inequality alone offered a
  /// *downgrade* as an update: hc-zwave running 0.1.5 against a registry still
  /// carrying 0.1.4 showed "Update available — v0.1.4", a button that installs
  /// an older build. The plugins list never had the bug because it asks
  /// [RegistryPlugin.updateFrom], which has always compared.
  ///
  /// Newer than *both* the record and the running process, because either one
  /// being ahead means there is nothing to fetch.
  bool wouldInstall(String? latest) {
    if (latest == null || latest.isEmpty) return false;
    final have = [installedVersion, version]
        .whereType<String>()
        .where((v) => v.isNotEmpty)
        .toList();
    if (have.isEmpty) return false;
    return have.every((v) => RegistryPlugin.compareVersions(latest, v) > 0);
  }

  /// A heartbeat within ~90s means the supervisor still hears from the child.
  bool get heartbeatHealthy {
    final h = lastHeartbeat;
    if (h == null) return false;
    return DateTime.now().toUtc().difference(h).inSeconds < 90;
  }
}
