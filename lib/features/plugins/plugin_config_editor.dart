import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/widget_registry.dart';
import '../../core/models/plugin_config.dart';
import '../../core/models/plugin_entry.dart';
import '../../core/providers/plugin_config_provider.dart';
import '../../core/providers/plugins_provider.dart';
import '../../core/schema/plugin_config_schema.dart';
import '../../design/hc_icons.dart';
import '../../design/skins.dart';
import '../../design/tokens.dart';
import '../../shell/hc_sheet.dart';

/// Open the plugin's config editor as a sheet: a schema-driven typed form when
/// the plugin published a schema, with a raw-TOML tab as the fallback / escape.
Future<void> showPluginConfigEditor(
    BuildContext context, WidgetRef ref, PluginEntry plugin) {
  return showHcSheet(
    context,
    title: '${plugin.displayName} configuration',
    child: Theme(
      data: hcTheme(HcSkin.midnight),
      child: _EditorLoader(plugin),
    ),
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
    final config = doc.valueOrNull;
    if (config == null) {
      return _pad(Text('This plugin exposes no editable configuration.',
          style: TextStyle(color: t.surface.onBaseMuted)));
    }
    return _ConfigForm(
      plugin: plugin,
      doc: config,
      fields: fields.valueOrNull,
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

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header + tabs
        Padding(
          padding: EdgeInsets.fromLTRB(t.space.md, t.space.md, t.space.sm, 0),
          child: Row(children: [
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
        for (final path in f.objectArrays) _ArrayNote(t, path, widget.doc),
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

/// A read-only note for an `array<object>` (e.g. Hue bridges) the flat form
/// can't edit — pointing at the Raw TOML tab.
class _ArrayNote extends StatelessWidget {
  const _ArrayNote(this.t, this.path, this.doc);
  final HcTokens t;
  final String path;
  final PluginConfigDoc doc;

  @override
  Widget build(BuildContext context) {
    final items = doc.config?[path];
    final count = items is List ? items.length : 0;
    return Padding(
      padding: EdgeInsets.only(top: t.space.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(path.toUpperCase(),
            style: TextStyle(
                color: t.surface.onBaseMuted,
                fontSize: 10.5,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: t.surface.sunken,
            borderRadius: t.radius.smR,
            border: Border.all(color: t.stroke.hairline),
          ),
          child: Row(children: [
            Text('$count configured',
                style: TextStyle(color: t.surface.onBase, fontSize: 13.5)),
            const Spacer(),
            Text('Edit in Raw TOML',
                style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12.5)),
          ]),
        ),
      ]),
    );
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
