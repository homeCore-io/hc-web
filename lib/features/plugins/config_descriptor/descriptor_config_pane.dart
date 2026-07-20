import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/areas_provider.dart';
import '../../../core/providers/devices_provider.dart';
import '../../../core/providers/plugin_config_provider.dart';
import '../../../core/providers/plugins_provider.dart';
import '../../../design/tokens.dart';
import 'descriptor.dart';
import 'descriptor_renderer.dart';

/// One section of a plugin's descriptor-driven config, mounted in the Studio's
/// config pane. The Studio's left rail picks the section; this renders it with
/// the [ConfigDescriptorRenderer], loads config + live sources, and persists on
/// save: regular fields → `putConfig`; source-bound rows → the live resource
/// (PATCH /devices).
class DescriptorConfigPane extends ConsumerStatefulWidget {
  const DescriptorConfigPane({
    super.key,
    required this.pluginId,
    required this.descriptor,
    required this.sectionId,
  });

  final String pluginId;
  final ConfigDescriptor descriptor;
  final String sectionId;

  @override
  ConsumerState<DescriptorConfigPane> createState() =>
      _DescriptorConfigPaneState();
}

class _DescriptorConfigPaneState extends ConsumerState<DescriptorConfigPane> {
  bool _saving = false;

  CfgSection get _section => widget.descriptor.sections.firstWhere(
        (s) => s.id == widget.sectionId,
        orElse: () => widget.descriptor.sections.first,
      );

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final doc = ref.watch(pluginConfigProvider(widget.pluginId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              t.space.lg, t.space.lg, t.space.lg, t.space.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_section.title,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: t.surface.onBase)),
              Text('Operator settings — changes apply on save (restarts the plugin).',
                  style:
                      TextStyle(fontSize: 12, color: t.surface.onBaseMuted)),
            ],
          ),
        ),
        Expanded(
          child: doc.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text('Could not load config: $e',
                    style: TextStyle(color: t.accent.warn))),
            data: (cfg) {
              final values = Map<String, dynamic>.from(cfg?.config ?? const {});
              return ConfigDescriptorRenderer(
                descriptor: widget.descriptor,
                onlySectionId: widget.sectionId,
                initialValues: values,
                saving: _saving,
                sourceData: _resolveSources(),
                // callback_host defaults to the address homeCore is served on
                // (the interface the operator reaches it through).
                dynamicDefaults: {'api.callback_host': Uri.base.host},
                onSave: _save,
              );
            },
          ),
        ),
      ],
    );
  }

  /// Resolve the live rows behind each `source` ref a descriptor can reference.
  ///
  /// These are the generic `core_resource` refs any plugin may bind to:
  /// - `devices` — the devices **this plugin** owns (its rows, its identity).
  /// - `areas`   — the house's rooms, for `select` options.
  ///
  /// (`sonos_devices` is kept as an alias so the local hand-authored fixture
  /// still resolves if the plugin-served descriptor is unavailable.)
  Map<String, List<Map<String, dynamic>>> _resolveSources() {
    final devices = ref.watch(devicesProvider).valueOrNull ?? const [];
    final areas = ref.watch(areasProvider).valueOrNull ?? const [];
    final mine = [
      for (final d in devices)
        if (d.pluginId == widget.pluginId)
          {
            'device_id': d.id,
            'name': d.name ?? d.displayName,
            'area': d.area ?? '',
          },
    ];
    return {
      'devices': mine,
      'sonos_devices': mine,
      'areas': [
        for (final a in areas)
          {'value': a['name'] ?? a['id'], 'label': a['name'] ?? a['id']},
      ],
    };
  }

  Future<void> _save(
    Map<String, dynamic> values,
    Map<String, Map<Object?, Map<String, dynamic>>> edits,
  ) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(pluginsApiProvider)
          .putConfig(widget.pluginId, config: values);
      final devicesApi = ref.read(devicesApiProvider);
      for (final rows in edits.values) {
        for (final entry in rows.entries) {
          await devicesApi.updateDevice('${entry.key}', entry.value);
        }
      }
      ref.invalidate(pluginConfigProvider(widget.pluginId));
      ref.invalidate(devicesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
