import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/devices_provider.dart';
import '../../core/providers/plugin_config_provider.dart';
import '../../core/providers/plugins_provider.dart';
import '../../design/skins.dart';
import '../../design/tokens.dart';

/// Presents the results of a plugin `discover_devices` action and lets the user
/// add each found device to the plugin's `[[devices]]` config.
///
/// Adding writes the entry via the config API (no restart); the plugin is
/// restarted once when the dialog closes so it registers everything just added.
/// The discovered→config mapping is WLED-shaped (`{ip, name}` → `{host, hc_id,
/// name}`); a plugin whose config uses a different device array would need its
/// own mapping here.
class DiscoveryResultsDialog extends ConsumerStatefulWidget {
  const DiscoveryResultsDialog({
    super.key,
    required this.pluginId,
    required this.discovered,
  });

  final String pluginId;
  final List<Map<String, dynamic>> discovered;

  @override
  ConsumerState<DiscoveryResultsDialog> createState() =>
      _DiscoveryResultsDialogState();
}

class _DiscoveryResultsDialogState
    extends ConsumerState<DiscoveryResultsDialog> {
  Map<String, dynamic> _config = {};
  final Set<String> _added = {}; // host keys already-in-config or just added
  final Set<String> _adding = {}; // in-flight host keys
  final Set<String> _newHcIds = {}; // hc_ids written this session, to await

  bool _dirty = false; // wrote config → needs a restart on close
  bool _loading = true;
  bool _restarting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await ref.read(pluginsApiProvider).getConfig(widget.pluginId);
      final cfg = Map<String, dynamic>.from(doc?.config ?? const {});
      setState(() {
        _config = cfg;
        _added.addAll(_existingHosts(cfg));
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Set<String> _existingHosts(Map cfg) {
    final devs = cfg['devices'];
    if (devs is! List) return {};
    return devs
        .whereType<Map>()
        .map((d) => '${d['host'] ?? ''}')
        .where((h) => h.isNotEmpty)
        .toSet();
  }

  String _hostOf(Map<String, dynamic> d) => '${d['ip'] ?? d['host'] ?? ''}';

  String _nameOf(Map<String, dynamic> d) => '${d['name'] ?? d['ip'] ?? 'WLED'}'
      .replaceAll(RegExp(r'\.local\.?$'), '');

  String _deriveHcId(Map<String, dynamic> d, Set<String> taken) {
    final base = _nameOf(d)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    var id = base.isEmpty ? 'wled' : base;
    var n = 2;
    while (taken.contains(id)) {
      id = '${base}_$n';
      n++;
    }
    return id;
  }

  Future<void> _add(Map<String, dynamic> d) async {
    final host = _hostOf(d);
    if (host.isEmpty) return;
    setState(() {
      _adding.add(host);
      _error = null;
    });
    try {
      final api = ref.read(pluginsApiProvider);
      final devs = (_config['devices'] is List)
          ? List<dynamic>.from(_config['devices'] as List)
          : <dynamic>[];
      if (!devs.any((e) => e is Map && '${e['host']}' == host)) {
        final taken = devs.whereType<Map>().map((e) => '${e['hc_id']}').toSet();
        final hcId = _deriveHcId(d, taken);
        devs.add({'host': host, 'hc_id': hcId, 'name': _nameOf(d)});
        _config['devices'] = devs;
        await api.putConfig(widget.pluginId, config: _config);
        _newHcIds.add(hcId);
      }
      setState(() {
        _adding.remove(host);
        _added.add(host);
        _dirty = true;
      });
    } catch (e) {
      setState(() {
        _adding.remove(host);
        _error = '$e';
      });
    }
  }

  Future<void> _close() async {
    if (!_dirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() => _restarting = true);
    try {
      // The plugin registers devices only at startup, so a restart is what
      // makes the entries we just wrote become live devices.
      await ref.read(pluginsApiProvider).lifecycle(widget.pluginId, 'restart');
      await ref.read(pluginsProvider.notifier).settle(widget.pluginId);
      // Registration lags the restart ack by a few seconds — wait for the new
      // devices to actually appear before refreshing, or the overview count
      // (from the plugin record) reads the pre-restart state.
      await _awaitRegistered();
    } catch (_) {
      // Config is written regardless; a failed restart just delays registration
      // until the next start. Don't trap the user in the dialog.
    }
    ref.invalidate(pluginConfigProvider(widget.pluginId));
    ref.invalidate(pluginsProvider);
    ref.invalidate(devicesProvider);
    if (mounted) Navigator.of(context).pop();
  }

  /// Poll the device list until every device we just wrote has registered, or
  /// ~13s elapses. Bounded so an unreachable device can't trap the dialog — the
  /// config is saved regardless and the device appears once it registers.
  Future<void> _awaitRegistered() async {
    if (_newHcIds.isEmpty) return;
    final api = ref.read(devicesApiProvider);
    for (var i = 0; i < 18; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      try {
        final raw = await api.listDevices();
        final present = raw
            .map((m) => '${(m as Map)['device_id'] ?? m['id'] ?? ''}')
            .toSet();
        if (_newHcIds.every(present.contains)) return;
      } catch (_) {
        // transient — keep polling
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: hcTheme(HcSkin.midnight),
      child: Builder(builder: (context) {
        final t = HcTokens.of(context);
        return Dialog(
          backgroundColor: t.surface.raised,
          shape: RoundedRectangleBorder(borderRadius: t.radius.lgR),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Discovered devices',
                      style: TextStyle(
                          color: t.surface.onBase,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    _loading
                        ? 'Loading current config…'
                        : '${widget.discovered.length} found · add the ones you want.',
                    style:
                        TextStyle(color: t.surface.onBaseMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final d in widget.discovered) _row(t, d),
                          ],
                        ),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!,
                        style:
                            TextStyle(color: t.accent.danger, fontSize: 12.5)),
                  ],
                  const SizedBox(height: 18),
                  Row(children: [
                    if (_dirty)
                      Expanded(
                        child: Text('Added devices register when you close.',
                            style: TextStyle(
                                color: t.surface.onBaseMuted, fontSize: 12)),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _restarting ? null : _close,
                      style: FilledButton.styleFrom(
                          backgroundColor: t.accent.active,
                          foregroundColor: t.accent.onPrimary),
                      child: _restarting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_dirty ? 'Done' : 'Close'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _row(HcTokens t, Map<String, dynamic> d) {
    final host = _hostOf(d);
    final added = _added.contains(host);
    final adding = _adding.contains(host);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: t.radius.mdR,
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Row(children: [
        Icon(Icons.lightbulb_outline_rounded, size: 19, color: t.accent.active),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_nameOf(d),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: t.surface.onBase,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              if (host.isNotEmpty)
                Text(host,
                    style: TextStyle(
                        color: t.surface.onBaseMuted,
                        fontSize: 12,
                        fontFeatures: t.numericFontFeatures)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (added)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_rounded, size: 15, color: t.accent.success),
            const SizedBox(width: 4),
            Text('Added',
                style: TextStyle(
                    color: t.accent.success,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ])
        else
          OutlinedButton(
            onPressed: (adding || host.isEmpty) ? null : () => _add(d),
            style: OutlinedButton.styleFrom(
              foregroundColor: t.accent.active,
              side: BorderSide(color: t.accent.active.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: adding
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Add'),
          ),
      ]),
    );
  }
}
