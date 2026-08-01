/// A condition a plugin reports about itself, from `PluginRecord.notices`.
///
/// `status` says whether the process is alive. This says whether it can do its
/// job — the two are not the same, and the gap is where operators get stuck. An
/// Ecowitt receiver bound to loopback starts cleanly, heartbeats, and reports
/// `active` while every gateway upload is dropped. Before notices the only
/// trace was a line in the log at startup, and this sheet showed a healthy
/// plugin with zero devices and no explanation.
///
/// Notices are current state, not history: the plugin republishes the full set
/// on every heartbeat and core replaces what it held, so anything shown here is
/// still true as of the last beat. A resolved condition disappears on its own —
/// there is deliberately nothing to dismiss.
class PluginNotice {
  const PluginNotice({
    required this.level,
    required this.code,
    required this.message,
    this.remedy,
  });

  /// 'info' | 'warning' | 'error'. Kept as a string rather than an enum so an
  /// unknown level from a newer plugin renders as-is instead of crashing the
  /// sheet; [isError] treats only the known-bad value as bad.
  final String level;

  /// Stable identifier, e.g. `receiver_unreachable`. The wording of [message]
  /// may change between plugin versions; this does not.
  final String code;
  final String message;

  /// Concrete fix, when the plugin can name one. Rendered under the message.
  final String? remedy;

  factory PluginNotice.fromJson(Map<String, dynamic> json) => PluginNotice(
        level: json['level'] as String? ?? 'warning',
        code: json['code'] as String? ?? '',
        message: json['message'] as String? ?? '',
        remedy: json['remedy'] as String?,
      );

  bool get isError => level == 'error';
  bool get isInfo => level == 'info';
}
