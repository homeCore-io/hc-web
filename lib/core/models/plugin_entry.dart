import '../text/humanize.dart';

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
  });

  final String pluginId;

  /// "active" | "offline" | "stopped" | "starting" | "unknown".
  final String status;
  final String registeredAt;
  final bool enabled;

  /// Local child process (true) vs remote MQTT-only (false).
  final bool managed;
  final int deviceCount;
  final String? version;

  /// Installed artifact version (registry/managed plugins), for "update available".
  final String? installedVersion;
  final DateTime? uptimeStarted;
  final DateTime? lastHeartbeat;
  final String? configPath;
  final bool supportsManagement;

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
      );

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

  /// A heartbeat within ~90s means the supervisor still hears from the child.
  bool get heartbeatHealthy {
    final h = lastHeartbeat;
    if (h == null) return false;
    return DateTime.now().toUtc().difference(h).inSeconds < 90;
  }
}
