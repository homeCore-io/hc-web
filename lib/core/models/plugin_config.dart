/// A plugin's operator config as returned by `GET /plugins/{id}/config`.
///
/// Core hands back the TOML text (`raw`) for local file-config plugins and the
/// same document parsed to JSON (`config`); remote plugins answer over an MQTT
/// RPC and have `format == "remote"` with only `config`. Secrets are redacted to
/// the literal `__redacted__` on the way out and restored on `PUT`, so a
/// fetch→edit→save round-trip never destroys a credential.
class PluginConfigDoc {
  const PluginConfigDoc({
    required this.pluginId,
    required this.format,
    this.raw,
    this.config,
    this.redacted = true,
  });

  final String pluginId;

  /// `"toml"` for a local file-config plugin, `"remote"` for an MQTT RPC one.
  final String format;

  /// The exact TOML text (comments + layout preserved). Null for remote plugins.
  final String? raw;

  /// The config parsed to JSON, when it parsed. The typed form edits this.
  final Map<String, dynamic>? config;

  /// Whether secret-valued keys came back as `__redacted__`.
  final bool redacted;

  bool get isRemote => format == 'remote';
  bool get hasRaw => raw != null && raw!.isNotEmpty;

  factory PluginConfigDoc.fromJson(Map<dynamic, dynamic> j) => PluginConfigDoc(
        pluginId: '${j['plugin_id']}',
        format: '${j['format']}',
        raw: j['raw'] as String?,
        config: j['config'] == null
            ? null
            : Map<String, dynamic>.from(j['config'] as Map),
        redacted: j['redacted'] == true,
      );
}
