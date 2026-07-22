import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/action_stream.dart';
import '../../../core/api/plugins_api.dart';
import '../../../core/models/device_state.dart';
import '../../../core/providers/areas_provider.dart';
import '../../../core/providers/devices_provider.dart';
import '../../../core/providers/plugin_config_provider.dart';
import '../../../core/providers/plugins_provider.dart';
import '../../../core/text/humanize.dart';
import '../../../design/tokens.dart';
import '../../../core/schema/plugin_capabilities.dart';
import 'config_merge.dart';
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

  /// A section whose fields all write to the live resource (Sonos's Speakers:
  /// a source-bound table) applies immediately — there is no save + restart, so
  /// the header must not promise one.
  bool get _sectionIsLiveResource {
    final fields = _section.fields;
    if (fields.isEmpty) return false;
    return fields.every((f) =>
        (f.kind == 'table' && f.source != null) ||
        f.kind == 'note' ||
        f.kind == 'link');
  }

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
              Text(
                  _sectionIsLiveResource
                      ? 'Changes take effect immediately.'
                      : 'Operator settings — changes apply on save (restarts the plugin).',
                  style: TextStyle(fontSize: 12, color: t.surface.onBaseMuted)),
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
              // The baseline a save diffs against — what this editor was shown,
              // which may already be behind the server.
              _loaded = Map<String, dynamic>.from(cfg?.config ?? const {});
              return ConfigDescriptorRenderer(
                descriptor: widget.descriptor,
                onlySectionId: widget.sectionId,
                initialValues: values,
                saving: _saving,
                sourceData: _resolveSources(),
                // callback_host defaults to the address homeCore is served on
                // (the interface the operator reaches it through).
                dynamicDefaults: {'api.callback_host': Uri.base.host},
                onCreateInSource: _createInSource,
                onSourceEdit: _saveSourceEdit,
                onImport: _runImport,
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
    // Each row carries the *effective* value plus the upstream one under
    // `<col>__source`. The renderer uses that to say "the bridge calls this X"
    // and to offer a revert — and because core treats "set it to the plugin's
    // own value" as agreement rather than a pin, reverting is simply writing
    // the source value back; no special clear-override call is needed.
    final mine = [
      for (final d in devices)
        if (d.pluginId == widget.pluginId)
          {
            'device_id': d.id,
            'name': d.displayName,
            'name__source': d.name ?? '',
            'area': d.effectiveArea ?? '',
            'area__source': d.area ?? '',
          },
    ];
    return {
      'devices': mine,
      'sonos_devices': mine,
      // Every device in the house, as pickable `{value: id, label: name}`.
      //
      // Deliberately NOT filtered to this plugin. A plugin whose config
      // *references* devices is usually referencing someone else's: a
      // thermostat averages temperature sensors from Z-Wave or Ecowitt and
      // switches a relay owned by Insteon. Filtering to `mine` would leave
      // those pickers permanently empty.
      //
      // The value stays the raw device id because that is what gets stored and
      // matched; only the label is the human name. Device names arrive human
      // already, so they are NOT humanized (see core/text/humanize.dart).
      'all_devices': [
        for (final d in devices) {'value': d.id, 'label': d.displayName},
      ],
      // Capability-filtered variants of the same list. A descriptor asks for
      // one with `source.capability`, and the renderer looks it up under
      // `all_devices#<capability>`.
      //
      // Filtered on what each device actually publishes rather than on
      // `supported_actions`, which hc-hue and hc-lutron do not send at all —
      // trusting it would empty every picker.
      for (final cap in _capabilitiesUsed())
        'all_devices#$cap': [
          for (final d in devices)
            if (_hasCapability(d, cap)) {'value': d.id, 'label': d.displayName},
        ],
      // Area keys are backend identifiers (`living_room`): the *value* must stay
      // raw so it round-trips, but the *label* is humanized so `snake_case`
      // never reaches a person. Device names, by contrast, already arrive human
      // and must NOT be title-cased (see core/text/humanize.dart).
      'areas': [
        for (final a in areas)
          {
            'value': a['name'] ?? a['id'],
            'label': humanize('${a['name'] ?? a['id']}'),
          },
      ],
    };
  }

  /// Capabilities this descriptor actually asks for, so no list is built that
  /// nothing renders.
  Set<String> _capabilitiesUsed() {
    final out = <String>{};
    void scan(CfgField f) {
      final c = f.source?.capability;
      if (c != null) out.add(c);
      for (final col in f.itemFields ?? const <CfgField>[]) {
        scan(col);
      }
    }

    for (final s in widget.descriptor.sections) {
      for (final f in s.fields) {
        scan(f);
      }
    }
    return out;
  }

  /// Can this device do the job the field is asking for?
  ///
  /// Deliberately about published state, not device_type alone: a plugin is
  /// free to call something a `switch`, but what decides whether a thermostat
  /// can drive it is whether it carries `on` and nothing dimmable.
  bool _hasCapability(DeviceState d, String capability) {
    switch (capability) {
      // Reports a temperature reading. Matching the attribute by name is what
      // lets the descriptor drop its "which attribute" field: if the device is
      // selectable, the answer is `temperature`.
      case 'temperature':
        return d.state.containsKey('temperature');
      // Binary on/off. `brightness` disqualifies a dimmer or lamp: driving one
      // from a thermostat would work but is never what was meant, and the
      // on/off payload stops being implied once a level is involved.
      case 'switch':
        return d.state.containsKey('on') &&
            !d.state.containsKey('brightness') &&
            !d.state.containsKey('brightness_pct');
      // An unknown capability filters nothing away rather than emptying the
      // picker — a newer plugin naming one this client has not learned yet
      // should degrade to "unfiltered", not to "no devices".
      default:
        return true;
    }
  }

  /// Create a new entry in a source-backed list. Only `areas` is creatable
  /// today — a plugin's own devices come from the plugin, not from a text box.
  ///
  /// This is the "create" half of match-or-create: picking an existing room
  /// matches it, and "New room…" must genuinely add it to the house rather
  /// than writing a free-text string onto one device. Returns core's
  /// normalized name so the caller selects the area that actually exists.
  Future<String?> _createInSource(String sourceRef, String name) async {
    if (sourceRef != 'areas') return name;
    try {
      final created = await ref.read(areasApiProvider).createArea(name);
      // The dropdown reads from areasProvider, so without this the room the
      // user just made would be missing from every other device's list until
      // a reload.
      ref.invalidate(areasProvider);
      // Core normalizes on create ("Studio B" → studio_b); return what it
      // stored, not what was typed.
      return '${created['name'] ?? name}';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create room: $e')),
        );
      }
      return null;
    }
  }

  /// Persist a single edit to a live source row — a Sonos speaker's name or
  /// room — the moment it's made. These are the live device registry, not
  /// plugin config: `PATCH /devices/:id`, no restart, nothing to "apply".
  Future<void> _saveSourceEdit(
      Object? rowKey, Map<String, dynamic> patch) async {
    if (rowKey == null) return;
    try {
      await ref.read(devicesApiProvider).updateDevice('$rowKey', patch);
      ref.invalidate(devicesProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  /// Hand pasted text to a plugin `import` action and return the rows it
  /// parsed. The renderer appends them; nothing is written until Save.
  ///
  /// These actions stream, so the POST only *starts* the run — the parsed rows
  /// arrive on the terminal SSE event. Failure terminals carry the plugin's own
  /// message ("That does not parse as JSON…"), which is far more use to the
  /// operator than a generic error, so it is thrown verbatim.
  Future<Map<String, dynamic>> _runImport(String actionId, String text) async {
    final api = ref.read(pluginsApiProvider);
    final action = PluginAction(id: actionId, label: actionId, stream: true);
    final outcome = await api.invoke(widget.pluginId, action, {'text': text});

    // A `CommandDone` here means the plugin answered without streaming, which
    // an import never does — treat it as a contract violation rather than
    // silently importing nothing.
    final requestId = switch (outcome) {
      CommandStreaming(:final requestId) => requestId,
      // Attach to a run already in flight instead of starting a second one.
      CommandBusy(:final activeRequestId) => activeRequestId,
      CommandDone() => null,
    };
    if (requestId == null) {
      throw 'The plugin answered without starting an import.';
    }

    final token =
        (await SharedPreferences.getInstance()).getString('jwt_token');
    if (token == null) throw 'Not signed in.';

    await for (final e in openActionStream(
      pluginId: widget.pluginId,
      requestId: requestId,
      token: token,
    )) {
      if (!e.stage.isTerminal) continue;
      if (e.stage.isFailure) throw e.message ?? 'the plugin reported a failure';
      final data = e.data;
      return data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
    }
    throw 'The import ended without a result.';
  }

  /// The config as it was when this editor rendered it.
  Map<String, dynamic> _loaded = const {};

  Future<void> _save(
    Map<String, dynamic> values,
    Map<String, Map<Object?, Map<String, dynamic>>> edits,
  ) async {
    setState(() => _saving = true);
    try {
      final api = ref.read(pluginsApiProvider);

      // Send what changed, not the copy this editor loaded. `PUT /config`
      // replaces the document, so sending a stale copy silently reverts
      // anything added since — which is how a Lutron repeater's host and
      // credentials once vanished on an otherwise ordinary save.
      final fresh = Map<String, dynamic>.from(
          (await api.getConfig(widget.pluginId))?.config ?? const {});
      final patch = diffConfig(_loaded, values);
      final clashes = conflictingPaths(_loaded, fresh, patch);
      if (clashes.isNotEmpty) {
        // Both edits are deliberate; only a person can say which wins.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              'Not saved — ${clashes.join(', ')} changed elsewhere since this '
              'page loaded. Reload to see the current values.',
            ),
          ));
          setState(() => _saving = false);
        }
        return;
      }

      await api.putConfig(widget.pluginId, config: applyPatch(fresh, patch));
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
