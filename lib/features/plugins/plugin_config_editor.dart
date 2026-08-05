import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/action_stream.dart';
import '../../core/api/plugins_api.dart';
import '../../core/dashboard/widget_registry.dart';
import '../../core/models/plugin_config.dart';
import '../../core/models/plugin_entry.dart';
import '../../core/providers/plugin_config_provider.dart';
import '../../core/providers/plugins_provider.dart';
import '../../core/schema/plugin_capabilities.dart';
import '../../core/schema/plugin_config_schema.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../../shell/hc_sheet.dart';
import 'plugin_actions.dart';

/// Open the plugin's config editor as a sheet: a schema-driven typed form when
/// the plugin published a schema, with a raw-TOML tab as the fallback / escape.
Future<void> showPluginConfigEditor(
    BuildContext context, WidgetRef ref, PluginEntry plugin) {
  return showHcSheet(
    context,
    title: '${plugin.displayName} configuration',
    child: _EditorLoader(plugin),
  );
}

class _EditorLoader extends ConsumerWidget {
  const _EditorLoader(this.plugin);
  final PluginEntry plugin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final doc = ref.watch(pluginConfigProvider(plugin.pluginId));
    final fields = ref.watch(pluginConfigFieldsProvider(plugin.pluginId));

    if (doc.isLoading || fields.isLoading) {
      return const SizedBox(
          height: 240, child: Center(child: CircularProgressIndicator()));
    }
    if (doc.hasError) {
      return _pad(Text('Could not load config: ${doc.error}',
          style: TextStyle(color: t.accent.danger)));
    }
    final config = doc.value;
    if (config == null) {
      return _pad(Text('This plugin exposes no editable configuration.',
          style: TextStyle(color: t.surface.onBaseMuted)));
    }
    return _ConfigForm(
      plugin: plugin,
      doc: config,
      fields: fields.value,
    );
  }

  Widget _pad(Widget child) =>
      Padding(padding: const EdgeInsets.all(28), child: child);
}

class _ConfigForm extends ConsumerStatefulWidget {
  const _ConfigForm({required this.plugin, required this.doc, this.fields});
  final PluginEntry plugin;
  final PluginConfigDoc doc;
  final SchemaFields? fields;

  @override
  ConsumerState<_ConfigForm> createState() => _ConfigFormState();
}

class _ConfigFormState extends ConsumerState<_ConfigForm> {
  late Map<String, dynamic> _flat; // edited scalar values (dotted keys)
  late final TextEditingController _toml;
  bool _rawMode = false;
  bool _saving = false;
  String? _error;

  /// The form fields: the plugin's published schema when it has one, otherwise
  /// inferred from the config values so the default view is never a text box.
  late final SchemaFields? _fields;
  bool get _hasForm {
    final f = _fields;
    return f != null && !f.isEmpty;
  }

  @override
  void initState() {
    super.initState();
    _flat = widget.doc.config == null ? {} : flattenConfig(widget.doc.config!);
    _toml = TextEditingController(text: widget.doc.raw ?? '');
    final schema = widget.fields;
    _fields = (schema != null && !schema.isEmpty)
        ? schema
        : (widget.doc.config != null
            ? inferFieldsFromConfig(widget.doc.config!)
            : null);
    // Only fall back to the raw view when there is genuinely no form to show.
    _rawMode = !_hasForm;
  }

  @override
  void dispose() {
    _toml.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final api = ref.read(pluginsApiProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_rawMode) {
        await api.putConfig(widget.plugin.pluginId, raw: _toml.text);
      } else {
        final validate = buildValidator(_fields!);
        final err = validate(_flat);
        if (err != null) {
          setState(() {
            _error = err;
            _saving = false;
          });
          return;
        }
        // Patch the original config with edited scalars — preserves arrays
        // (bridges) and anything the flat form doesn't cover.
        final patched = _deepCopy(widget.doc.config ?? {});
        _flat.forEach((k, v) => _setNested(patched, k, v));
        await api.putConfig(widget.plugin.pluginId, config: patched);
      }
      ref.invalidate(pluginConfigProvider(widget.plugin.pluginId));
      ref.invalidate(pluginsProvider);
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      setState(() {
        _error = '$e';
        _saving = false;
      });
    }
  }

  /// Remove a paired hub: confirm, invoke the plugin's `unpair_bridge` action
  /// (which unregisters the hub's devices + clears its stored key), then drop
  /// its entry from operator config so a restart can't resurrect it.
  Future<void> _removeBridge(Map<String, dynamic> bridge) async {
    final bridgeId = (bridge['bridge_id'] ?? '').toString().trim();
    final name = (bridge['name'] ?? '').toString().trim();
    final label =
        name.isNotEmpty ? name : (bridgeId.isNotEmpty ? bridgeId : 'this hub');
    if (bridgeId.isEmpty) {
      setState(() => _error = 'Cannot remove: this hub has no bridge_id');
      return;
    }

    final t = HcTokens.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove hub?'),
        content: Text(
            'Removes $label and all of its devices from homeCore, and clears '
            'its stored key. You can re-pair it later by pressing its link '
            'button.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Remove', style: TextStyle(color: t.accent.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // 1. Find + invoke unpair_bridge, awaiting its terminal event so the
      //    device-removal + key-clear finish BEFORE the config-PUT restart.
      final caps = await ref
          .read(pluginCapabilitiesProvider(widget.plugin.pluginId).future);
      final actions = caps?.actions ?? const <PluginAction>[];
      PluginAction? action;
      for (final a in actions) {
        if (a.id == 'unpair_bridge') {
          action = a;
          break;
        }
      }
      if (action == null) {
        throw 'this plugin has no "unpair_bridge" action — rebuild/restart it';
      }
      final api = ref.read(pluginsApiProvider);
      final outcome = await api
          .invoke(widget.plugin.pluginId, action, {'bridge_id': bridgeId});
      int removed = 0;
      switch (outcome) {
        case CommandDone(:final data):
          removed = _devicesRemoved(data);
        case CommandStreaming(:final requestId):
          removed = await _awaitUnpair(requestId);
        case CommandBusy(:final activeRequestId):
          removed = await _awaitUnpair(activeRequestId);
      }

      // 2. Drop the hub from operator config (no-op for learned-only hubs).
      //    The config watcher then restarts the plugin onto the clean state.
      await _dropBridgeFromConfig(bridgeId);

      ref.invalidate(pluginConfigProvider(widget.plugin.pluginId));
      ref.invalidate(pluginsProvider);
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Removed $label · $removed device${removed == 1 ? '' : 's'} unregistered')));
    } catch (e) {
      setState(() => _error = 'Remove failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Follow the streaming `unpair_bridge` action to its terminal event and
  /// return the reported device count. Throws on a failure terminal.
  Future<int> _awaitUnpair(String requestId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return 0;
    final events = openActionStream(
      pluginId: widget.plugin.pluginId,
      requestId: requestId,
      token: token,
    );
    await for (final e in events) {
      if (e.stage.isTerminal) {
        if (e.stage.isFailure) {
          throw e.message ?? 'the plugin reported a failure';
        }
        return _devicesRemoved(e.data);
      }
    }
    return 0;
  }

  int _devicesRemoved(Object? data) =>
      (data is Map && data['devices_removed'] is num)
          ? (data['devices_removed'] as num).toInt()
          : 0;

  Future<void> _dropBridgeFromConfig(String bridgeId) async {
    final config = widget.doc.config;
    if (config == null) return;
    final bridges = config['bridges'];
    if (bridges is! List) return;
    final kept = bridges
        .where((b) => !(b is Map &&
            (b['bridge_id'] ?? '').toString().toLowerCase() ==
                bridgeId.toLowerCase()))
        .toList();
    if (kept.length == bridges.length) {
      return; // learned-only; nothing in config
    }
    final patched = _deepCopy(config);
    patched['bridges'] = kept;
    await ref
        .read(pluginsApiProvider)
        .putConfig(widget.plugin.pluginId, config: patched);
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header: back to the plugin panel, title, tabs, close
        Padding(
          padding: EdgeInsets.fromLTRB(t.space.xs, t.space.md, t.space.sm, 0),
          child: Row(children: [
            IconButton(
              icon: Icon(Icons.arrow_back_rounded,
                  size: 20, color: t.surface.onBaseMuted),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Text('${widget.plugin.displayName} configuration',
                  style: TextStyle(
                      color: t.surface.onBase,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
            if (_hasForm && widget.doc.hasRaw) _tabs(t),
            IconButton(
              icon: Icon(HcIcons.x, size: 18, color: t.surface.onBaseMuted),
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ]),
        ),
        Divider(height: 1, color: t.stroke.hairline),
        Expanded(
          child: _rawMode ? _rawView(t) : _formView(t),
        ),
        // Save bar
        Divider(height: 1, color: t.stroke.hairline),
        Padding(
          padding: EdgeInsets.all(t.space.md),
          child: Row(children: [
            if (_error != null)
              Expanded(
                child: Text(_error!,
                    style: TextStyle(color: t.accent.danger, fontSize: 12.5)),
              )
            else
              Expanded(
                child: Text(
                    widget.plugin.managed
                        ? 'Saving restarts the plugin to apply'
                        : 'Applies live',
                    style: TextStyle(
                        color: t.surface.onBaseMuted.withValues(alpha: 0.8),
                        fontSize: 12)),
              ),
            TextButton(
              onPressed:
                  _saving ? null : () => Navigator.of(context).maybePop(),
              child: Text('Cancel', style: TextStyle(color: t.surface.onBase)),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: t.accent.active,
                foregroundColor: t.accent.onPrimary,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _tabs(HcTokens t) {
    Widget tab(String label, bool raw) {
      final sel = _rawMode == raw;
      return GestureDetector(
        onTap: () => setState(() => _rawMode = raw),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
          decoration: BoxDecoration(
            color: sel ? t.surface.raised : Colors.transparent,
            borderRadius: BorderRadius.circular(t.radius.pill),
          ),
          child: Text(label,
              style: TextStyle(
                  color: sel ? t.surface.onBase : t.surface.onBaseMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: BorderRadius.circular(t.radius.pill),
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        tab('Form', false),
        tab('Raw TOML', true),
      ]),
    );
  }

  Widget _rawView(HcTokens t) => Padding(
        padding: EdgeInsets.all(t.space.md),
        child: TextField(
          controller: _toml,
          maxLines: null,
          expands: true,
          style: const TextStyle(
              fontFamily: 'monospace', fontSize: 12.5, height: 1.5),
          decoration: InputDecoration(
            filled: true,
            fillColor: t.surface.sunken,
            border: OutlineInputBorder(
                borderRadius: t.radius.smR,
                borderSide: BorderSide(color: t.stroke.hairline)),
          ),
        ),
      );

  Widget _formView(HcTokens t) {
    final f = _fields!;
    // Group by section, preserving first-seen order.
    final order = <String>[];
    final bySection = <String, List<WidgetConfigField>>{};
    for (final field in f.fields) {
      // Hide the [homecore] connection/bootstrap block.
      if (isBootstrapConfigKey(field.name)) continue;
      final sec = f.sectionOf[field.name] ?? 'General';
      if (!bySection.containsKey(sec)) order.add(sec);
      bySection.putIfAbsent(sec, () => []).add(field);
    }

    return ListView(
      padding:
          EdgeInsets.fromLTRB(t.space.md, t.space.sm, t.space.md, t.space.md),
      children: [
        for (final sec in order) ...[
          _sectionLabel(t, sec),
          for (final field in bySection[sec]!)
            _FieldRow(
              field: field,
              value: _flat[field.name],
              secret: f.secretFields.contains(field.name),
              onChanged: (v) => setState(() {
                if (v == null) {
                  _flat.remove(field.name);
                } else {
                  _flat[field.name] = v;
                }
              }),
            ),
        ],
        for (final path in f.objectArrays)
          _ObjectArraySection(path, widget.doc, onRemove: _removeBridge),
      ],
    );
  }

  Widget _sectionLabel(HcTokens t, String s) => Padding(
        padding: EdgeInsets.only(top: t.space.md, bottom: t.space.xs),
        child: Text(s.toUpperCase(),
            style: TextStyle(
                color: t.surface.onBaseMuted,
                fontSize: 10.5,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700)),
      );
}

// ---------------------------------------------------------------------------

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.value,
    required this.secret,
    required this.onChanged,
  });
  final WidgetConfigField field;
  final Object? value;
  final bool secret;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Flexible(
                  child: Text(field.label ?? field.name,
                      style: TextStyle(color: t.surface.onBase, fontSize: 14)),
                ),
                if (field.required)
                  Text(' *', style: TextStyle(color: t.accent.danger)),
              ]),
              if (field.help != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(field.help!,
                      style: TextStyle(
                          color: t.surface.onBaseMuted.withValues(alpha: 0.8),
                          fontSize: 12)),
                ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        _control(context, t),
      ]),
    );
  }

  Widget _control(BuildContext context, HcTokens t) {
    switch (field.kind) {
      case WidgetConfigKind.boolean:
        return Switch(
          value: value == true,
          activeThumbColor: t.accent.active,
          onChanged: (v) => onChanged(v),
        );
      case WidgetConfigKind.choice:
        final opts = field.options ?? const [];
        return DropdownButton<String>(
          value: value?.toString(),
          underline: const SizedBox.shrink(),
          dropdownColor: t.surface.overlay,
          items: [
            for (final o in opts)
              DropdownMenuItem(value: o, child: Text(o.toUpperCase())),
          ],
          onChanged: (v) => onChanged(v),
        );
      case WidgetConfigKind.integer:
        return _TextInput(
          initial: value?.toString() ?? '',
          width: 96,
          numeric: true,
          // num, not int: inferred configs contain doubles (thresholds, lat/lon).
          onChanged: (s) => onChanged(num.tryParse(s)),
        );
      case WidgetConfigKind.stringList:
        final list = value is List ? (value as List).join(', ') : '';
        return _TextInput(
          initial: list,
          width: 180,
          onChanged: (s) => onChanged(s
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()),
        );
      default: // text / url / secret
        if (secret) {
          return _TextInput(
            initial: '',
            width: 150,
            obscure: true,
            hint: value == redactedSentinel ? 'unchanged' : null,
            // Empty means "leave the stored secret alone".
            onChanged: (s) => onChanged(s.isEmpty ? redactedSentinel : s),
          );
        }
        return _TextInput(
          initial: value?.toString() ?? '',
          width: 150,
          onChanged: onChanged,
        );
    }
  }
}

class _TextInput extends StatefulWidget {
  const _TextInput({
    required this.initial,
    required this.onChanged,
    this.width = 140,
    this.numeric = false,
    this.obscure = false,
    this.hint,
  });
  final String initial;
  final ValueChanged<String> onChanged;
  final double width;
  final bool numeric;
  final bool obscure;
  final String? hint;

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _c,
        obscureText: widget.obscure,
        textAlign: widget.numeric ? TextAlign.right : TextAlign.start,
        keyboardType: widget.numeric ? TextInputType.number : null,
        style: TextStyle(color: t.surface.onBase, fontSize: 13.5),
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hint,
          hintStyle: TextStyle(color: t.surface.onBaseMuted, fontSize: 13),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          filled: true,
          fillColor: t.surface.sunken,
          enabledBorder: OutlineInputBorder(
              borderRadius: t.radius.smR,
              borderSide: BorderSide(color: t.stroke.hairline)),
          focusedBorder: OutlineInputBorder(
              borderRadius: t.radius.smR,
              borderSide: BorderSide(color: t.stroke.focus)),
        ),
      ),
    );
  }
}

/// Lists each object in an `array<object>` (e.g. Hue bridges / paired hubs).
/// The flat form can't show these, and with more than one hub you need to see
/// which are which and which are paired — a bare "N configured" count doesn't.
class _ObjectArraySection extends StatelessWidget {
  const _ObjectArraySection(this.path, this.doc, {this.onRemove});
  final String path;
  final PluginConfigDoc doc;

  /// Per-item destructive action (Remove hub). Null hides the row menu.
  final void Function(Map<String, dynamic> item)? onRemove;

  static const _primaryKeys = [
    'name',
    'label',
    'title',
    'bridge_id',
    'id',
    'host',
    'ip'
  ];
  static const _subtitleKeys = [
    'host',
    'ip',
    'address',
    'bridge_id',
    'serial',
    'model'
  ];

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final raw = doc.config?[path];
    final items = raw is List
        ? raw.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList()
        : const <Map<String, dynamic>>[];

    return Padding(
      padding: EdgeInsets.only(top: t.space.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(path.toUpperCase(),
              style: TextStyle(
                  color: t.surface.onBaseMuted,
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text('${items.length}',
              style: TextStyle(
                  color: t.surface.onBaseMuted.withValues(alpha: 0.65),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        if (items.isEmpty)
          _card(t,
              child: Text('None paired yet',
                  style: TextStyle(color: t.surface.onBaseMuted, fontSize: 13)))
        else
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _row(t, items[i], i),
          ],
      ]),
    );
  }

  Widget _card(HcTokens t, {required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: t.surface.sunken,
          borderRadius: t.radius.smR,
          border: Border.all(color: t.stroke.hairline),
        ),
        child: child,
      );

  Widget _row(HcTokens t, Map<String, dynamic> item, int i) {
    final title = _primary(item, i);
    final sub = _subtitle(item, title);
    return _card(
      t,
      child: Row(children: [
        Icon(Icons.router_rounded, size: 20, color: t.surface.onBaseMuted),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: TextStyle(
                      color: t.surface.onBase,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              if (sub != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: t.surface.onBaseMuted,
                          fontSize: 12,
                          fontFeatures: t.numericFontFeatures)),
                ),
            ],
          ),
        ),
        if (_paired(item)) _pairedChip(t),
        if (onRemove != null) ...[
          const SizedBox(width: 2),
          _menu(t, item),
        ],
      ]),
    );
  }

  Widget _menu(HcTokens t, Map<String, dynamic> item) =>
      PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, size: 18, color: t.surface.onBaseMuted),
        tooltip: 'Hub actions',
        color: t.surface.overlay,
        onSelected: (v) {
          if (v == 'remove') onRemove!(item);
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'remove',
            child: Row(children: [
              Icon(HcIcons.trash, size: 15, color: t.accent.danger),
              const SizedBox(width: 10),
              Text('Remove hub', style: TextStyle(color: t.accent.danger)),
            ]),
          ),
        ],
      );

  Widget _pairedChip(HcTokens t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: t.accent.active.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(t.radius.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(HcIcons.check, size: 11, color: t.accent.active),
          const SizedBox(width: 4),
          Text('Paired',
              style: TextStyle(
                  color: t.accent.active,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
      );

  String _primary(Map<String, dynamic> item, int i) {
    for (final k in _primaryKeys) {
      final v = item[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return '${path.replaceAll(RegExp(r's$'), '')} ${i + 1}';
  }

  String? _subtitle(Map<String, dynamic> item, String title) {
    final parts = <String>[];
    for (final k in _subtitleKeys) {
      final v = item[k];
      if (v is String && v.isNotEmpty && v != title && !parts.contains(v)) {
        parts.add(v);
      }
      if (parts.length == 2) break;
    }
    return parts.isEmpty ? null : parts.join('  ·  ');
  }

  // Paired = a secret (app_key/token) is stored; on the wire it's the redacted
  // sentinel, so either that or any non-empty value counts.
  bool _paired(Map<String, dynamic> item) {
    for (final e in item.entries) {
      if (isSecretFieldName(e.key)) {
        final v = e.value;
        if (v == redactedSentinel || (v is String && v.isNotEmpty)) return true;
      }
    }
    return false;
  }
}

// ---------------------------------------------------------------------------

Map<String, dynamic> _deepCopy(Map<String, dynamic> m) {
  final out = <String, dynamic>{};
  m.forEach((k, v) {
    out[k] = v is Map
        ? _deepCopy(v.cast<String, dynamic>())
        : v is List
            ? List<dynamic>.from(v)
            : v;
  });
  return out;
}

void _setNested(Map<String, dynamic> root, String dotted, Object? value) {
  final parts = dotted.split('.');
  var cursor = root;
  for (var i = 0; i < parts.length - 1; i++) {
    final next = cursor[parts[i]];
    cursor = next is Map
        ? next.cast<String, dynamic>()
        : (cursor[parts[i]] = <String, dynamic>{});
  }
  cursor[parts.last] = value;
}
