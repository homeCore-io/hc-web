import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/devices_provider.dart';
import '../../../core/providers/plugin_config_provider.dart';
import '../../../core/providers/plugins_provider.dart';
import '../../../design/tokens.dart';
import 'descriptor.dart';
import 'descriptor_renderer.dart';
import 'sonos_fixture.dart';

/// Renderer-first preview harness for the Plugin Config Descriptor Protocol.
///
/// Renders the hand-authored Sonos descriptor (sonos_fixture.dart) against the
/// plugin's live config, so we can tune the application-like controls before
/// wiring the SDK / endpoint. Route: `/#/dev/config`. Dev scaffold — folds into
/// the Studio config pane once the vocabulary + controls settle.
class ConfigPreviewPage extends ConsumerStatefulWidget {
  const ConfigPreviewPage({super.key});

  @override
  ConsumerState<ConfigPreviewPage> createState() => _ConfigPreviewPageState();
}

class _ConfigPreviewPageState extends ConsumerState<ConfigPreviewPage> {
  static const _pluginId = 'plugin.sonos';
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final doc = ref.watch(pluginConfigProvider(_pluginId));

    return ColoredBox(
      color: t.surface.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                t.space.lg, t.space.lg, t.space.lg, t.space.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Config Descriptor Preview',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: t.surface.onBase)),
                Text('Sonos — rendered from a descriptor, not a schema form.',
                    style:
                        TextStyle(fontSize: 13, color: t.surface.onBaseMuted)),
              ],
            ),
          ),
          Expanded(
            child: doc.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Could not load config: $e',
                    style: TextStyle(color: t.accent.warn)),
              ),
              data: (cfg) {
                final descriptor =
                    ConfigDescriptor.fromJson(sonosDescriptorFixture);
                final values =
                    Map<String, dynamic>.from(cfg?.config ?? const {});
                // Resolve the descriptor's `sonos_devices` source from the live
                // device registry — the Speakers table binds to it.
                final devices =
                    ref.watch(devicesProvider).valueOrNull ?? const [];
                final speakers = [
                  for (final d in devices)
                    if (d.id.startsWith('sonos_'))
                      {
                        'device_id': d.id,
                        'name': d.name ?? d.displayName,
                        'area': d.area ?? '',
                      },
                ];
                return ConfigDescriptorRenderer(
                  descriptor: descriptor,
                  initialValues: values,
                  saving: _saving,
                  sourceData: {'sonos_devices': speakers},
                  onSave: _save,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save(
    Map<String, dynamic> values,
    Map<String, Map<Object?, Map<String, dynamic>>> edits,
  ) async {
    setState(() => _saving = true);
    try {
      await ref.read(pluginsApiProvider).putConfig(_pluginId, config: values);
      // Source-bound rows (Speakers) edit the live device registry, not config.
      final devicesApi = ref.read(devicesApiProvider);
      for (final rows in edits.values) {
        for (final entry in rows.entries) {
          await devicesApi.updateDevice('${entry.key}', entry.value);
        }
      }
      ref.invalidate(pluginConfigProvider(_pluginId));
      ref.invalidate(devicesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved (plugin will restart)')));
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
