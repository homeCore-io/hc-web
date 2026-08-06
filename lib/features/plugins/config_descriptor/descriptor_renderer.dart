import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../../core/text/humanize.dart';
import '../../../design/tokens.dart';
import 'attention_banner.dart';
import 'descriptor.dart';
import 'import_merge.dart';
import 'descriptor_validation.dart' as v;

/// Renders a [ConfigDescriptor] as an application-like editor: expressive
/// controls per field `kind`, live conditionals, list/table editors — the
/// design-system controls, composed from the plugin's own description.
///
/// Values are held in a mutable nested map (the plugin's config JSON) addressed
/// by each field's dotted `key`. On save it hands the whole map back.
class ConfigDescriptorRenderer extends StatefulWidget {
  const ConfigDescriptorRenderer({
    super.key,
    required this.descriptor,
    required this.initialValues,
    required this.onSave,
    this.saving = false,
    this.sourceData = const {},
    this.onlySectionId,
    this.dynamicDefaults = const {},
    this.onCreateInSource,
    this.onSourceEdit,
    this.onImport,
  });

  final ConfigDescriptor descriptor;
  final Map<String, dynamic> initialValues;

  /// Persist edits. [values] is the config document (regular fields); [edits]
  /// is per-source-field live-row edits — `{fieldKey: {rowKey: {col: val}}}` —
  /// which the host writes to the live resource (e.g. PATCH /devices), not the
  /// plugin config.
  final Future<void> Function(
    Map<String, dynamic> values,
    Map<String, Map<Object?, Map<String, dynamic>>> edits,
  ) onSave;
  final bool saving;

  /// Live rows for `source`-bound fields, keyed by the source `ref`. The host
  /// resolves the source (e.g. discovered devices); the renderer reconciles.
  final Map<String, List<Map<String, dynamic>>> sourceData;

  /// When set, render only this section (the Studio drives section nav via its
  /// left rail); otherwise render every section stacked (preview harness).
  final String? onlySectionId;

  /// Runtime-computed defaults keyed by field key — override the descriptor's
  /// static default (e.g. `api.callback_host` → the address homeCore is served
  /// on). Applied when the config has no stored value.
  final Map<String, Object?> dynamicDefaults;

  /// Create a new entry in a `source`-backed list and return the canonical
  /// value to select — e.g. "New room…" on an `areas`-bound select actually
  /// creates the area in homeCore and returns its normalized name.
  ///
  /// Without this, "add new" only stuffed the typed text into the field, so a
  /// new room was never a real area: it existed as a string on one device,
  /// showed up in no other device's dropdown, and was invisible to everything
  /// else in the house. The host owns the create because only it knows what
  /// `ref` means; the renderer just asks.
  ///
  /// Returning null cancels the selection (create failed or was refused).
  final Future<String?> Function(String ref, String name)? onCreateInSource;

  /// Persist one edit to a `source`-bound row immediately (e.g. PATCH
  /// /devices/:id). Source rows are the **live resource**, not plugin config:
  /// a speaker's room is true the moment you pick it, and there is nothing to
  /// "apply" to the plugin afterwards.
  ///
  /// Staging these behind Save was actively misleading — creating a room wrote
  /// through at once while assigning the speaker to it silently waited for a
  /// button, so the room appeared and the assignment seemed to vanish.
  final Future<void> Function(Object? rowKey, Map<String, dynamic> patch)?
      onSourceEdit;

  /// Run an `import` field's plugin action over pasted text and return the
  /// rows it parsed, keyed by target field.
  ///
  /// The plugin parses because only it knows its vendor's export format; the
  /// renderer appends because config is core-owned and must stay reviewable —
  /// imported rows land unsaved, exactly as if they had been typed.
  ///
  /// Throws with a human-readable message the field surfaces verbatim.
  final Future<Map<String, dynamic>> Function(String action, String text)?
      onImport;

  @override
  State<ConfigDescriptorRenderer> createState() =>
      _ConfigDescriptorRendererState();
}

class _ConfigDescriptorRendererState extends State<ConfigDescriptorRenderer> {
  late Map<String, dynamic> _values;
  final Map<String, Object?> _defaults = {};

  /// Edits to source-bound rows, destined for the live resource, not config:
  /// `{fieldKey: {rowKey: {col: val}}}`.
  final Map<String, Map<Object?, Map<String, dynamic>>> _sourceEdits = {};

  // ── list tables: which rows are open, picked, searched or filtered ───────
  final Map<String, Set<int>> _tableExpanded = {};
  final Map<String, Set<int>> _tableSelection = {};
  final Map<String, String> _tableQuery = {};
  final Set<String> _tableFilter = {};

  // ── import fields: paste buffer, in-flight set, and last outcome ──────────
  final Map<String, TextEditingController> _importText = {};
  final Set<String> _importBusy = {};
  final Map<String, String> _importNote = {};
  final Set<String> _importFailed = {};

  @override
  void initState() {
    super.initState();
    _values = _deepCopy(widget.initialValues);
    // Index every field's default by key so conditionals evaluate against the
    // *effective* value (stored ?? default). Without this, a gate like
    // `visible_when: api.enabled truthy` reads null for an unsaved default-true
    // toggle and wrongly hides its dependents.
    for (final s in widget.descriptor.sections) {
      for (final f in s.fields) {
        if (f.key != null) _defaults[f.key!] = f.defaultValue;
      }
    }
    _defaults.addAll(widget.dynamicDefaults);
  }

  /// Effective read for conditionals: stored value, else the field's default.
  Object? _readEff(String key) => _get(key) ?? _defaults[key];

  // ── nested get/set by dotted key ──────────────────────────────────────────
  Object? _get(String key) {
    Object? cur = _values;
    for (final part in key.split('.')) {
      if (cur is Map && cur.containsKey(part)) {
        cur = cur[part];
      } else {
        return null;
      }
    }
    return cur;
  }

  void _set(String key, Object? value) {
    final parts = key.split('.');
    Map<String, dynamic> cur = _values;
    for (var i = 0; i < parts.length - 1; i++) {
      final next = cur[parts[i]];
      if (next is Map<String, dynamic>) {
        cur = next;
      } else {
        cur = (cur[parts[i]] = <String, dynamic>{});
      }
    }
    setState(() => cur[parts.last] = value);
  }

  Object? _effective(CfgField f) => f.key == null
      ? f.defaultValue
      : (_get(f.key!) ?? _defaults[f.key!] ?? f.defaultValue);

  bool _visible(CfgField f) => f.visibleWhen?.evaluate(_readEff) ?? true;

  /// A whole section can be conditional too — YoLink's cloud credentials do
  /// not apply to a local hub. Evaluated against the same effective values as
  /// field conditions, so switching the mode field updates it live.
  bool _sectionVisible(CfgSection s) =>
      s.visibleWhen?.evaluate(_readEff) ?? true;
  bool _isRequired(CfgField f) =>
      f.required || (f.requiredWhen?.evaluate(_readEff) ?? false);

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final only = widget.onlySectionId;
    final sections = [
      for (final s in widget.descriptor.sections)
        if (!s.hidden && _sectionVisible(s) && (only == null || s.id == only))
          s,
    ];
    // Only show Save when a visible field actually writes to plugin config on
    // save. A section that is nothing but a live-resource table (Sonos's
    // Speakers) has nothing to apply — its edits already wrote through — so a
    // Save button there is a button that does nothing, which is what prompted
    // "why is there a save button?".
    final hasConfigToSave =
        sections.any((s) => s.fields.where(_visible).any(v.savesToConfig));

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                t.space.lg, t.space.lg, t.space.lg, t.space.xl),
            children: [for (final s in sections) _section(t, s)],
          ),
        ),
        if (hasConfigToSave) _saveBar(t),
      ],
    );
  }

  Widget _section(HcTokens t, CfgSection s) {
    final fields = s.fields.where(_visible).toList();
    if (fields.isEmpty) return const SizedBox.shrink();
    final showHeader = widget.onlySectionId == null;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
            Text(s.title.toUpperCase(),
                style: t.text.captionStyle.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: t.surface.onBaseMuted)),
          if (s.help != null)
            Padding(
              padding: EdgeInsets.only(top: t.space.xs),
              child: Text(s.help!,
                  style: t.text.bodySmallStyle
                      .copyWith(color: t.surface.onBaseMuted)),
            ),
          SizedBox(height: t.space.md),
          for (final f in fields) _field(t, f),
        ],
      ),
    );
  }

  Widget _field(HcTokens t, CfgField f) {
    switch (f.kind) {
      case 'note':
        return _note(t, f);
      case 'link':
        return _link(t, f);
      case 'list':
        return _listEditor(t, f);
      case 'table':
        return _tableEditor(t, f);
      case 'import':
        return _importField(t, f);
      default:
        return _scalarRow(t, f);
    }
  }

  /// Paste-and-parse. The plugin action turns pasted text into rows; we append
  /// them to the declared targets, unsaved, so they can be reviewed and edited
  /// like any typed row.
  Widget _importField(HcTokens t, CfgField f) {
    final key = f.key ?? f.action ?? 'import';
    final controller = _importText[key] ??= TextEditingController();
    final busy = _importBusy.contains(key);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labelBlock(t, f),
          SizedBox(height: t.space.sm),
          TextField(
            controller: controller,
            maxLines: 6,
            minLines: 3,
            style: t.text.resolve(t.text.bodySmall, mono: true),
            decoration: InputDecoration(
              hintText: f.placeholder,
              hintStyle: t.text.bodySmallStyle.copyWith(
                  color: t.surface.onBaseMuted.withValues(alpha: 0.5)),
              filled: true,
              fillColor: t.surface.raised,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.radius.sm),
                borderSide: BorderSide(color: t.stroke.hairline),
              ),
            ),
          ),
          SizedBox(height: t.space.sm),
          Row(children: [
            _AddButton(
              label: busy ? 'Importing…' : 'Import',
              onPressed: busy ? null : () => _runImport(f, controller.text),
            ),
            if (_importNote[key] != null)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: t.space.sm),
                  child: Text(
                    _importNote[key]!,
                    style: t.text.bodySmallStyle.copyWith(
                        color: _importFailed.contains(key)
                            ? t.accent.warn
                            : t.surface.onBaseMuted),
                  ),
                ),
              ),
          ]),
        ],
      ),
    );
  }

  /// Run the action, then append what it returned to each declared target.
  ///
  /// Rows already present are skipped rather than duplicated, matched on the
  /// target table's `key_by` — pasting the same report twice is a no-op, which
  /// is what an operator re-checking their work expects.
  Future<void> _runImport(CfgField f, String text) async {
    final key = f.key ?? f.action ?? 'import';
    final run = widget.onImport;
    final action = f.action;
    if (run == null || action == null) return;

    setState(() {
      _importBusy.add(key);
      _importNote.remove(key);
      _importFailed.remove(key);
    });
    try {
      final result = await run(action, text);
      var added = 0;
      var skipped = 0;
      var updated = 0;
      for (final target in f.targets ?? const <String>[]) {
        final incoming = result[target];
        if (incoming is! List) continue;
        final table = _fieldByKey(target);
        final existing = _rowsFor(target);
        final idKey = table?.keyBy;
        final outcome = mergeImportedRows(existing, incoming, idKey);
        added += outcome.added;
        updated += outcome.updated;
        skipped += outcome.skipped;
        _set(target, existing);
      }
      final summary = result['summary'];
      setState(() {
        _importNote[key] = [
          if (summary is String && summary.isNotEmpty) summary,
          if (added > 0) 'Added $added row${added == 1 ? '' : 's'}.',
          if (updated > 0)
            'Filled in new details on $updated existing row'
                '${updated == 1 ? '' : 's'}.',
          if (skipped > 0) 'Skipped $skipped already up to date.',
          if (added == 0 && skipped == 0 && updated == 0) 'Nothing to add.',
        ].join(' ');
      });
    } catch (e) {
      setState(() {
        _importFailed.add(key);
        _importNote[key] = '$e';
      });
    } finally {
      if (mounted) setState(() => _importBusy.remove(key));
    }
  }

  /// The declared field for `key`, searched across every section.
  CfgField? _fieldByKey(String key) {
    for (final s in widget.descriptor.sections) {
      for (final f in s.fields) {
        if (f.key == key) return f;
      }
    }
    return null;
  }

  /// Current rows of an array field, as a mutable copy.
  List<Map<String, dynamic>> _rowsFor(String key) {
    final raw = _get(key);
    return raw is List
        ? [for (final r in raw) Map<String, dynamic>.from(r as Map)]
        : <Map<String, dynamic>>[];
  }

  // ── scalar row: [label + help | control] ──────────────────────────────────
  Widget _scalarRow(HcTokens t, CfgField f) {
    // Label beside control, until there is no room for both.
    //
    // The controls are a fixed 240 wide. Beside them the label had whatever was
    // left, and on a narrow window that is a column a few characters across —
    // so "Bind address. 0.0.0.0 = all interfaces" rendered one letter per line.
    // Below the breakpoint the two stack instead, which is the same
    // information in the order you read it.
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.sm),
      child: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _labelBlock(t, f),
              SizedBox(height: t.space.sm),
              Align(alignment: Alignment.centerLeft, child: _control(t, f)),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _labelBlock(t, f)),
            SizedBox(width: t.space.md),
            _control(t, f),
          ],
        );
      }),
    );
  }

  Widget _labelBlock(HcTokens t, CfgField f) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Flexible(
                child: Text(f.label ?? humanize(f.key?.split('.').last),
                    style: t.text.subtitleStyle
                        .copyWith(color: t.surface.onBase))),
            if (_isRequired(f))
              Text('  •  required',
                  style: t.text.captionStyle.copyWith(color: t.accent.warn)),
          ]),
          if (f.help != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(f.help!,
                  style: t.text.bodySmallStyle.copyWith(
                      color: t.surface.onBaseMuted.withValues(alpha: 0.85))),
            ),
        ],
      );

  Widget _control(HcTokens t, CfgField f) {
    final v = _effective(f);
    switch (f.kind) {
      case 'toggle':
        return Switch(
          value: v == true,
          activeThumbColor: t.accent.active,
          onChanged: (b) => _set(f.key!, b),
        );
      case 'select':
        return _selectControl(t, f, v, (val) => _set(f.key!, val));
      case 'enum':
        final opts = f.options ?? const [];
        if (f.render == 'segmented' && opts.length <= 6) {
          return _Segmented(
            options: opts,
            value: v,
            onChanged: (val) => _set(f.key!, val),
          );
        }
        return DropdownButton<Object?>(
          value: v,
          underline: const SizedBox.shrink(),
          dropdownColor: t.surface.overlay,
          items: [
            for (final o in opts)
              DropdownMenuItem(value: o.value, child: Text(o.label)),
          ],
          onChanged: (val) => _set(f.key!, val),
        );
      case 'int':
      case 'number':
      case 'duration':
      case 'port':
        return _Input(
          key: ValueKey(f.key),
          initial: v?.toString() ?? '',
          width: 128,
          numeric: true,
          suffix: f.unit ?? (f.kind == 'port' ? null : null),
          validate: (s) => _validateScalar(f, s),
          // Unparseable text is kept as text rather than becoming null. Null
          // reads as "unset", so a typo silently *cleared* the field and saved
          // happily; keeping the text makes it a value the save bar can refuse.
          onChanged: (s) => _set(f.key!, _coerceScalar(f, s)),
        );
      case 'secret':
        return _Input(
          key: ValueKey(f.key),
          initial: '',
          width: 200,
          obscure: true,
          hint: v == '__redacted__' ? 'unchanged' : null,
          onChanged: (s) => _set(f.key!, s.isEmpty ? '__redacted__' : s),
        );
      default: // text, host, ip, cidr, url, mac, email
        return _Input(
          key: ValueKey(f.key),
          initial: v?.toString() ?? '',
          width: 240,
          placeholder: f.placeholder,
          validate: (s) => _validateScalar(f, s),
          onChanged: (s) => _set(f.key!, s),
        );
    }
  }

  static final Object _createSentinel = Object();

  /// A dropdown of options (inline or from a `source`), with an optional
  /// "add new" that prompts for a value not in the list.
  Widget _selectControl(
      HcTokens t, CfgField f, Object? value, ValueChanged<Object?> onChanged) {
    final opts = _optionsFor(f);
    final empty = value == null || '$value'.isEmpty;
    final display = empty
        ? (f.placeholder ?? 'Select')
        : opts
            .firstWhere((o) => o.value == value,
                orElse: () =>
                    CfgOption(value: value, label: humanize('$value')))
            .label;
    return PopupMenuButton<Object?>(
      tooltip: '',
      color: t.surface.overlay,
      position: PopupMenuPosition.under,
      itemBuilder: (_) => [
        for (final o in opts)
          PopupMenuItem(
              value: o.value,
              child: Text(o.label,
                  style:
                      t.text.subtitleStyle.copyWith(color: t.surface.onBase))),
        if (f.allowCreate) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: _createSentinel,
            child: Row(children: [
              Icon(Icons.add, size: 16, color: t.accent.active),
              const SizedBox(width: 6),
              Text('New ${(f.label ?? 'value').toLowerCase()}…',
                  style: TextStyle(color: t.accent.active)),
            ]),
          ),
        ],
      ],
      onSelected: (v) async {
        if (!identical(v, _createSentinel)) {
          onChanged(v);
          return;
        }
        final name = await _promptNew(f.label ?? 'value');
        if (name == null || name.isEmpty) return;

        // Actually create it in the resource this select is bound to, and
        // select the canonical value the host hands back — core normalizes
        // ("Studio B" → studio_b), so selecting the typed text would pin a
        // value that does not match the area that now exists.
        final ref = f.source?.ref;
        final create = widget.onCreateInSource;
        if (ref == null || create == null) {
          onChanged(name);
          return;
        }
        final created = await create(ref, name);
        if (created != null) onChanged(created);
      },
      child: Container(
        width: 240,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: t.surface.sunken,
          borderRadius: BorderRadius.circular(t.radius.sm),
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Row(children: [
          Expanded(
            child: Text(display,
                style: t.text.subtitleStyle.copyWith(
                    color: empty
                        ? t.surface.onBaseMuted.withValues(alpha: 0.7)
                        : t.surface.onBase)),
          ),
          Icon(Icons.expand_more, size: 18, color: t.surface.onBaseMuted),
        ]),
      ),
    );
  }

  List<CfgOption> _optionsFor(CfgField f) {
    if (f.options != null) return f.options!;
    final key = f.source?.dataKey;
    final items = key == null ? const [] : (widget.sourceData[key] ?? const []);
    return [
      for (final m in items)
        CfgOption(
          value: m['value'] ?? m['name'] ?? m['id'],
          label: '${m['label'] ?? m['name'] ?? m['value'] ?? m['id']}',
        ),
    ];
  }

  Future<String?> _promptNew(String what) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final t = HcTokens.of(ctx);
        return AlertDialog(
          backgroundColor: t.surface.raised,
          title: Text('New ${what.toLowerCase()}',
              style: TextStyle(color: t.surface.onBase)),
          content: TextField(
            controller: c,
            autofocus: true,
            style: TextStyle(color: t.surface.onBase),
            decoration: const InputDecoration(hintText: 'Name'),
            onSubmitted: (_) => Navigator.pop(ctx, c.text.trim()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: t.accent.active,
                  foregroundColor: t.surface.base),
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  /// A field that opens an external URL (the plugin's own web interface).
  Widget _link(HcTokens t, CfgField f) {
    final url = _hrefFor(f.href ?? '');
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.sm),
      child: Row(children: [
        Expanded(child: _labelBlock(t, f)),
        SizedBox(width: t.space.md),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: t.accent.active.withValues(alpha: 0.15),
            foregroundColor: t.accent.active,
            elevation: 0,
          ),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Open'),
          onPressed: () => web.window.open(url, '_blank'),
        ),
      ]),
    );
  }

  String _hrefFor(String template) {
    var s = template.replaceAll('{client_host}', web.window.location.hostname);
    s = s.replaceAllMapped(RegExp(r'\{([a-zA-Z0-9_.]+)\}'), (m) {
      final key = m.group(1)!;
      return '${_get(key) ?? _defaults[key] ?? ''}';
    });
    return s;
  }

  Widget _columnControl(
      HcTokens t, CfgField c, String initial, ValueChanged<String> onChanged,
      {Key? key, ValueChanged<String>? onCommit}) {
    if (c.kind == 'select') {
      return _selectControl(t, c, initial.isEmpty ? null : initial,
          (v) => onChanged('${v ?? ''}'));
    }
    // A bool column needs a switch for the same reason an enum needs a
    // dropdown: left as a text box it stores the *string* "true", which fails
    // to deserialize into the plugin's bool. Absent cell reads as false, which
    // matches serde's `#[serde(default)]`.
    if (c.kind == 'toggle') {
      return Switch(
        value: initial == 'true',
        activeThumbColor: t.accent.active,
        onChanged: (b) => onChanged('$b'),
      );
    }
    // A list column is comma-separated text, not the stacked add/remove editor
    // a section-level list gets — that control is taller than a table row and
    // these lists are short (a keypad's button components). `_coerceColumn`
    // parses it back into a real JSON array.
    // A list bound to a source is a *set of references* — pick them, don't
    // type them. See _MultiSelect.
    if (c.kind == 'list' && c.source != null) {
      return _MultiSelect(
        options: _optionsFor(c),
        selected: v.splitCsv(initial),
        placeholder: c.placeholder,
        onChanged: (ids) => onChanged(ids.join(', ')),
      );
    }
    if (c.kind == 'list') {
      final item = c.itemKind ?? 'text';
      return _Input(
        key: key,
        initial: initial,
        placeholder: c.placeholder ?? (v.isNumericKind(item) ? '1, 2, 3' : ''),
        validate: (s) => v.validateCsv(item, s),
        onChanged: onChanged,
        onCommit: onCommit,
      );
    }
    const numericKinds = {'int', 'number', 'port', 'duration'};
    return _Input(
      key: key,
      initial: initial,
      placeholder: c.placeholder,
      numeric: numericKinds.contains(c.kind),
      onChanged: onChanged,
      onCommit: onCommit,
    );
  }

  // ── list<scalar> editor (e.g. manual_hosts: list<host>) ───────────────────
  Widget _listEditor(HcTokens t, CfgField f) {
    final raw = _effective(f);
    final items = raw is List ? List<Object?>.from(raw) : <Object?>[];
    void write(List<Object?> next) => _set(f.key!, next);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labelBlock(t, f),
          SizedBox(height: t.space.sm),
          if (items.isEmpty)
            Text('None yet.',
                style: t.text.bodySmallStyle.copyWith(
                    color: t.surface.onBaseMuted.withValues(alpha: 0.7))),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: t.space.sm),
              child: Row(children: [
                Expanded(
                  child: _Input(
                    key: ValueKey('${f.key}[$i]'),
                    initial: items[i]?.toString() ?? '',
                    placeholder: _placeholderFor(f.itemKind),
                    validate: (s) => v.validateKind(f.itemKind ?? 'text', s,
                        allowEmpty: true),
                    onChanged: (s) {
                      items[i] = s;
                      write(List<Object?>.from(items));
                    },
                  ),
                ),
                IconButton(
                  icon:
                      Icon(Icons.close, size: 18, color: t.surface.onBaseMuted),
                  onPressed: () {
                    items.removeAt(i);
                    write(List<Object?>.from(items));
                  },
                ),
              ]),
            ),
          _AddButton(
            label: 'Add ${(f.itemKind ?? 'item')}',
            onPressed: () {
              items.add('');
              write(List<Object?>.from(items));
            },
          ),
        ],
      ),
    );
  }

  // ── table (array of objects). With a `source`, reconcile live rows against
  //    stored overrides; without, edit the stored array directly.
  Widget _tableEditor(HcTokens t, CfgField f) {
    if (f.source != null) return _sourcedTable(t, f);
    if (f.render == 'list') return _listTable(t, f);
    return _manualTable(t, f);
  }

  // ── list table ────────────────────────────────────────────────────────────
  //
  // A card per row costs ~150px, so a dozen devices is a wall of scrolling and
  // twenty is unusable. This renders one line each — the fields you scan by —
  // and opens the full editor only for the row you are working on.

  /// Rows of `f`, as a mutable copy, paired with their index in the stored
  /// list. Filtering and grouping reorder what is shown, but every edit still
  /// has to address the row where it actually lives.
  List<({int index, Map<String, dynamic> row})> _indexedRows(CfgField f) =>
      indexedRowsOf(_effective(f));

  void _writeRows(
      CfgField f, List<({int index, Map<String, dynamic> row})> all) {
    _set(f.key!, [for (final e in all) e.row]);
  }

  /// Does this row still want attention — any column declaring
  /// `prompt_when_empty` that has no value?
  bool _rowNeedsAttention(CfgField f, Map<String, dynamic> row) =>
      AttentionBanner.rowNeedsAttention(f, row);

  String _cellText(CfgField c, Object? v) {
    if (v == null || (v is String && v.isEmpty)) return '';
    if (c.options != null) {
      for (final o in c.options!) {
        if ('${o.value}' == '$v') return o.label;
      }
    }
    return _columnInitial(c, v);
  }

  Widget _listTable(HcTokens t, CfgField f) {
    final key = f.key!;
    final all = _indexedRows(f);
    final cols = f.itemFields ?? const <CfgField>[];
    final query = (_tableQuery[key] ?? '').trim().toLowerCase();
    final onlyAttention = _tableFilter.contains(key);
    final selected = _tableSelection[key] ??= <int>{};

    final attentionCount =
        all.where((e) => _rowNeedsAttention(f, e.row)).length;

    var shown = all;
    if (onlyAttention) {
      shown = shown.where((e) => _rowNeedsAttention(f, e.row)).toList();
    }
    if (query.isNotEmpty) {
      shown = shown.where((e) {
        final hay = [
          for (final c in cols)
            if (c.key != null) _cellText(c, e.row[c.key]),
          ...e.row.values.map((v) => '$v'),
        ].join(' ').toLowerCase();
        return hay.contains(query);
      }).toList();
    }

    // Group only when the descriptor says how, and keep the empty bucket last
    // so "unassigned" reads as leftovers rather than a place.
    final groupKey = f.groupBy;
    final groups = <String, List<({int index, Map<String, dynamic> row})>>{};
    if (groupKey != null) {
      final col = cols.where((c) => c.key == groupKey).firstOrNull;
      for (final e in shown) {
        final label = col == null
            ? '${e.row[groupKey] ?? ''}'
            : _cellText(col, e.row[groupKey]);
        groups.putIfAbsent(label.isEmpty ? '' : label, () => []).add(e);
      }
    } else {
      groups[''] = shown;
    }
    final orderedGroups = groups.keys.toList()
      ..sort((a, b) => a.isEmpty
          ? 1
          : b.isEmpty
              ? -1
              : a.compareTo(b));

    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labelBlock(t, f),
          SizedBox(height: t.space.sm),
          if (all.length > 4 || attentionCount > 0)
            _listToolbar(t, f, all.length, attentionCount),
          if (attentionCount > 0)
            AttentionBanner(field: f, count: attentionCount),
          if (selected.isNotEmpty) _bulkBar(t, f, all, selected),
          Container(
            decoration: BoxDecoration(
              // Rows sit on `raised`, group bands on `sunken`. Against the bare
              // page ground all three were the same near-black and the
              // structure vanished.
              color: t.surface.raised,
              border: Border.all(color: t.stroke.hairline),
              borderRadius: BorderRadius.circular(t.radius.md),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              if (shown.isEmpty)
                Padding(
                  padding: EdgeInsets.all(t.space.lg),
                  child: Text(
                    all.isEmpty
                        ? 'No ${_plural(f)} yet — add one below.'
                        : 'No ${_plural(f)} match that search.',
                    style: t.text.bodySmallStyle
                        .copyWith(color: t.surface.onBaseMuted),
                  ),
                ),
              for (final g in orderedGroups) ...[
                if (groupKey != null)
                  _groupHeader(
                      t, g.isEmpty ? 'Unassigned' : g, groups[g]!.length),
                for (final e in groups[g]!)
                  _listRow(t, f, e, cols, selected, all,
                      last: e == groups[g]!.last),
              ],
            ]),
          ),
          SizedBox(height: t.space.sm),
          _AddButton(
            label: 'Add ${_singular(f)}',
            onPressed: () {
              final next = _indexedRows(f);
              next.add((index: next.length, row: newRowFor(cols)));
              _writeRows(f, next);
              setState(() => _tableExpanded
                  .putIfAbsent(key, () => <int>{})
                  .add(next.length - 1));
            },
          ),
        ],
      ),
    );
  }

  Widget _listToolbar(HcTokens t, CfgField f, int total, int attention) {
    final key = f.key!;
    final onlyAttention = _tableFilter.contains(key);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: Row(children: [
        Expanded(
          child: _Input(
            key: ValueKey('$key.__search'),
            initial: _tableQuery[key] ?? '',
            placeholder: 'Search ${_plural(f)}',
            onChanged: (s) => setState(() => _tableQuery[key] = s),
          ),
        ),
        if (attention > 0) ...[
          SizedBox(width: t.space.sm),
          _FilterChip(
            label: 'Needs attention',
            count: attention,
            selected: onlyAttention,
            onTap: () => setState(() => onlyAttention
                ? _tableFilter.remove(key)
                : _tableFilter.add(key)),
          ),
        ],
        SizedBox(width: t.space.sm),
        Text('$total',
            style: t.text.bodySmallStyle.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: t.surface.onBaseMuted)),
      ]),
    );
  }

  /// Applying one value to many rows is the difference between two
  /// interactions and twenty — an imported report lands a whole tableful of
  /// rows all wanting the same answer.
  Widget _bulkBar(HcTokens t, CfgField f,
      List<({int index, Map<String, dynamic> row})> all, Set<int> selected) {
    final cols = f.itemFields ?? const <CfgField>[];
    // Only columns offering a fixed set of choices can be applied blind; free
    // text across twenty rows is a mistake waiting to happen. Source-bound
    // columns count — assigning a room to everything in a report is exactly
    // the tedium this exists to remove.
    final settable =
        cols.where((c) => c.key != null && _optionsFor(c).isNotEmpty);
    return Container(
      margin: EdgeInsets.only(bottom: t.space.sm),
      padding:
          EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
      decoration: BoxDecoration(
        color: t.accent.active.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(t.radius.sm),
      ),
      child: Row(children: [
        Text('${selected.length} selected',
            style: t.text.bodyStyle.copyWith(
                fontWeight: FontWeight.w600, color: t.surface.onBase)),
        SizedBox(width: t.space.md),
        for (final c in settable) ...[
          _BulkSet(
            label: 'Set ${(c.label ?? c.key!).toLowerCase()}…',
            options: _optionsFor(c),
            onPicked: (value) {
              final next = _indexedRows(f);
              for (final e in next) {
                if (selected.contains(e.index)) e.row[c.key!] = value;
              }
              _writeRows(f, next);
              setState(() => selected.clear());
            },
          ),
          SizedBox(width: t.space.sm),
        ],
        const Spacer(),
        TextButton(
          onPressed: () {
            final next = _indexedRows(f)
                .where((e) => !selected.contains(e.index))
                .toList();
            _writeRows(f, next);
            setState(() {
              selected.clear();
              _tableExpanded[f.key!]?.clear();
            });
          },
          child: Text('Remove', style: TextStyle(color: t.accent.warn)),
        ),
        TextButton(
          onPressed: () => setState(selected.clear),
          child: Text('Cancel', style: TextStyle(color: t.surface.onBaseMuted)),
        ),
      ]),
    );
  }

  Widget _groupHeader(HcTokens t, String label, int count) => Container(
        width: double.infinity,
        padding:
            EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
        decoration: BoxDecoration(
          color: t.surface.sunken,
          border: Border(
            top: BorderSide(color: t.stroke.hairline),
            bottom: BorderSide(color: t.stroke.hairline),
          ),
        ),
        child: Row(children: [
          Text(humanize(label).toUpperCase(),
              style: t.text.overlineStyle.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: t.surface.onBaseMuted)),
          SizedBox(width: t.space.xs),
          Text('· $count',
              style: t.text.overlineStyle.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: t.surface.onBaseMuted)),
        ]),
      );

  Widget _listRow(
    HcTokens t,
    CfgField f,
    ({int index, Map<String, dynamic> row}) entry,
    List<CfgField> cols,
    Set<int> selected,
    List<({int index, Map<String, dynamic> row})> all, {
    required bool last,
  }) {
    final key = f.key!;
    final expanded =
        (_tableExpanded[key] ?? const <int>{}).contains(entry.index);
    final isSelected = selected.contains(entry.index);
    final needs = _rowNeedsAttention(f, entry.row);

    // The first text column titles the row; the identity column trails it.
    final titleCol = cols.firstWhere(
        (c) => c.kind == 'text' && c.key != f.groupBy,
        orElse: () => cols.isEmpty ? CfgField(kind: 'text') : cols.first);
    final idCol = f.keyBy == null
        ? null
        : cols.where((c) => c.key == f.keyBy).firstOrNull;
    final title = _cellText(titleCol, entry.row[titleCol.key]);
    final promptCol = cols.where((c) => c.promptWhenEmpty).firstOrNull;

    return Column(children: [
      InkWell(
        hoverColor: t.surface.overlay,
        onTap: () => setState(() {
          final open = _tableExpanded.putIfAbsent(key, () => <int>{});
          expanded ? open.remove(entry.index) : open.add(entry.index);
        }),
        child: Container(
          color: isSelected
              ? t.accent.active.withValues(alpha: 0.07)
              : Colors.transparent,
          padding: EdgeInsets.symmetric(
              horizontal: t.space.sm, vertical: t.space.sm),
          child: Row(children: [
            SizedBox(
              width: 30,
              child: Checkbox(
                value: isSelected,
                visualDensity: VisualDensity.compact,
                activeColor: t.accent.active,
                onChanged: (v) => setState(() => v == true
                    ? selected.add(entry.index)
                    : selected.remove(entry.index)),
              ),
            ),
            Expanded(
              child: Text(title.isEmpty ? 'Untitled' : title,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.bodyStyle.copyWith(
                      color: title.isEmpty
                          ? t.surface.onBaseMuted
                          : t.surface.onBase)),
            ),
            if (idCol != null) ...[
              Text('#${_cellText(idCol, entry.row[idCol.key])}',
                  style: t.text.bodySmallStyle.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: t.surface.onBaseMuted)),
              SizedBox(width: t.space.sm),
            ],
            if (promptCol != null)
              _StateChip(
                label: needs
                    ? 'Set ${(promptCol.label ?? promptCol.key!).toLowerCase()}'
                    : _cellText(promptCol, entry.row[promptCol.key]),
                attention: needs,
              ),
            Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                size: 18, color: t.surface.onBaseMuted),
          ]),
        ),
      ),
      if (expanded)
        Container(
          width: double.infinity,
          color: t.surface.sunken,
          padding: EdgeInsets.fromLTRB(
              t.space.lg, t.space.sm, t.space.md, t.space.md),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // A generated column is identity the client minted; there is
            // nothing to show and nothing to edit.
            for (final c in cols)
              if (c.key != null && !c.generated)
                _rowField(t, f, entry.index, c),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: Icon(Icons.close, size: 16, color: t.accent.warn),
                label: Text('Remove', style: TextStyle(color: t.accent.warn)),
                onPressed: () {
                  final next = _indexedRows(f)
                    ..removeWhere((e) => e.index == entry.index);
                  _writeRows(f, next);
                  setState(() => _tableExpanded[key]?.clear());
                },
              ),
            ),
          ]),
        ),
      if (!last) Divider(height: 1, thickness: 1, color: t.stroke.hairline),
    ]);
  }

  Widget _rowField(HcTokens t, CfgField f, int rowIndex, CfgField c) {
    final rows = _indexedRows(f);
    final entry = rows.where((e) => e.index == rowIndex).firstOrNull;
    if (entry == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(
          width: 132,
          child: Text(c.label ?? c.key!,
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted)),
        ),
        Expanded(
          child: c.readOnly
              ? Text(_cellText(c, entry.row[c.key]),
                  style: t.text.bodyStyle.copyWith(color: t.surface.onBase))
              : _columnControl(
                  t,
                  c,
                  _columnInitial(c, entry.row[c.key]),
                  (s) {
                    final next = _indexedRows(f);
                    for (final e in next) {
                      if (e.index == rowIndex) {
                        e.row[c.key!] = _coerceColumn(c, s);
                      }
                    }
                    _writeRows(f, next);
                  },
                  key: ValueKey('${f.key}[$rowIndex].${c.key}'),
                ),
        ),
      ]),
    );
  }

  /// Live-bound table: one card per discovered item, prefilled from the stored
  /// override (or the live value), editing writes only the override row back.
  Widget _sourcedTable(HcTokens t, CfgField f) {
    final src = f.source!;
    final live = widget.sourceData[src.dataKey] ?? const [];
    final keyBy = f.keyBy ?? src.itemKey ?? 'id';
    final cols = f.itemFields ?? const [];
    final edits = _sourceEdits[f.key!] ??= {};

    // Keep the local echo so the card reflects the edit instantly, then write
    // through to the live resource. When there is no write-through host the
    // edit stays staged for the save bar (the preview harness).
    void setCol(Object? k, String col, String val, {bool commit = true}) {
      setState(() => (edits[k] ??= {})[col] = val);
      final write = widget.onSourceEdit;
      if (commit && write != null) write(k, {col: val});
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labelBlock(t, f),
          SizedBox(height: t.space.sm),
          if (live.isEmpty)
            Text('No devices discovered yet.',
                style: t.text.bodySmallStyle.copyWith(
                    color: t.surface.onBaseMuted.withValues(alpha: 0.7))),
          for (final item in live)
            Builder(builder: (_) {
              final k = item[keyBy];
              final rowEdits = edits[k];
              final edited = rowEdits != null && rowEdits.isNotEmpty;
              final title = rowEdits?['name'] ??
                  (src.labels?['title'] != null
                      ? item[src.labels!['title']]
                      : k);
              final subtitle = src.labels?['subtitle'] != null
                  ? item[src.labels!['subtitle']]
                  : null;
              return Container(
                margin: EdgeInsets.only(bottom: t.space.sm),
                padding: EdgeInsets.all(t.space.md),
                decoration: BoxDecoration(
                  color: t.surface.raised,
                  borderRadius: BorderRadius.circular(t.radius.md),
                  border: Border.all(
                      color: edited
                          ? t.accent.active.withValues(alpha: 0.5)
                          : t.stroke.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.speaker_outlined,
                          size: 18, color: t.surface.onBaseMuted),
                      SizedBox(width: t.space.sm),
                      Text('$title',
                          style: t.text.subtitleStyle.copyWith(
                              fontWeight: FontWeight.w600,
                              color: t.surface.onBase)),
                      if (subtitle != null) ...[
                        SizedBox(width: t.space.sm),
                        Text('$subtitle',
                            style: t.text.bodySmallStyle
                                .copyWith(color: t.surface.onBaseMuted)),
                      ],
                      const Spacer(),
                      if (edited) _pill(t, 'edited'),
                    ]),
                    SizedBox(height: t.space.sm),
                    for (final c in cols)
                      if (!c.generated)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: t.space.xs),
                          child: Row(children: [
                            SizedBox(
                                width: 90,
                                child: Text(c.label ?? c.key ?? '',
                                    style: t.text.bodyStyle.copyWith(
                                        color: t.surface.onBaseMuted))),
                            Expanded(
                              child: _columnControl(
                                t,
                                c,
                                _columnInitial(
                                    c, rowEdits?[c.key] ?? item[c.key]),
                                // A dropdown commits on selection; a text field
                                // echoes locally per keystroke and commits on
                                // blur/submit, so we don't PATCH per character.
                                (s) => setCol(k, c.key!, s,
                                    commit: c.kind == 'select'),
                                onCommit: (s) => setCol(k, c.key!, s),
                                key: ValueKey('${f.key}.$k.${c.key}'),
                              ),
                            ),
                            // When the row carries the upstream value, say so and
                            // offer a way back to it. Overriding is a deliberate
                            // act, so it should be visible and reversible.
                            ..._overrideAffordance(t, c, item, rowEdits,
                                (v) => setCol(k, c.key!, v)),
                          ]),
                        ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Show whether a sourced column currently differs from the value the owning
  /// system reports, and offer a one-tap revert.
  ///
  /// A row may carry `<col>__source` — the upstream value (what the bridge calls
  /// the device). When the effective value differs, the user has pinned an
  /// override; reverting just writes the source value back, which the API reads
  /// as agreement and clears the pin.
  List<Widget> _overrideAffordance(
    HcTokens t,
    CfgField c,
    Map<String, dynamic> row,
    Map<String, dynamic>? rowEdits,
    ValueChanged<String> setValue,
  ) {
    final source = row['${c.key}__source'];
    // Only an *override* when the plugin actually reports a value to override.
    // Sonos reports no room, so `area__source` is empty — assigning a room
    // there is a plain assignment, not an override, and labelling it
    // "overridden" (as it did) is just wrong. A speaker's name, which Sonos
    // does report, still shows the affordance.
    if (source == null || '$source'.isEmpty) return const [];
    final current = '${rowEdits?[c.key] ?? row[c.key] ?? ''}';
    if (current == '$source') return const [];
    final label = c.kind == 'select' ? humanize('$source') : '$source';
    return [
      SizedBox(width: t.space.sm),
      Tooltip(
        message: 'Overrides the plugin, which reports "$label" — tap to revert',
        child: InkWell(
          onTap: () => setValue('$source'),
          borderRadius: BorderRadius.circular(t.radius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.undo, size: 14, color: t.accent.active),
              const SizedBox(width: 4),
              Text('overridden',
                  style: t.text.captionStyle.copyWith(color: t.accent.active)),
            ]),
          ),
        ),
      ),
    ];
  }

  Widget _pill(HcTokens t, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: t.accent.active.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: t.text.captionStyle
                .copyWith(fontWeight: FontWeight.w600, color: t.accent.active)),
      );

  /// What this table's rows are *called*, taken from the field itself. This
  /// renderer is shared by every plugin, so its empty state and add button
  /// cannot name a specific device — Hue's Bridges section read "No speakers
  /// pinned … Add speaker" until this was derived rather than hardcoded.
  String _plural(CfgField f) =>
      (f.label ?? humanize(f.key ?? 'entries')).toLowerCase();

  /// Naive singularization, which is all a UI noun needs: "Bridges" → "bridge",
  /// "Entries" → "entry". A plugin wanting better wording gives the field a
  /// label that reads well either way.
  String _singular(CfgField f) {
    final p = _plural(f);
    if (p.endsWith('ies') && p.length > 3) {
      return '${p.substring(0, p.length - 3)}y';
    }
    if (p.endsWith('ses') || p.endsWith('xes') || p.endsWith('zes')) {
      return p.substring(0, p.length - 2);
    }
    if (p.endsWith('s') && !p.endsWith('ss')) {
      return p.substring(0, p.length - 1);
    }
    return p;
  }

  /// Convert a manual-table cell's text to the JSON type its column declares,
  /// so numeric config fields round-trip. An empty numeric cell becomes null
  /// (the field is absent) rather than 0, which would be a real value.
  /// Same contract as [_coerceColumn], for a scalar field's own control.
  Object? _coerceScalar(CfgField f, String s) {
    if (s.isEmpty) return null;
    return f.kind == 'number' ? (num.tryParse(s) ?? s) : (int.tryParse(s) ?? s);
  }

  Object? _coerceColumn(CfgField c, String s) {
    switch (c.kind) {
      case 'int':
      case 'port':
      case 'duration':
        return s.isEmpty ? null : (int.tryParse(s) ?? s);
      case 'number':
        return s.isEmpty ? null : (num.tryParse(s) ?? s);
      case 'toggle':
        return s == 'true';
      case 'list':
        // Empty means "no entries", i.e. an empty array — not a null, which
        // would drop the key and read back as a missing field.
        final item = c.itemKind ?? 'text';
        return v
            .splitCsv(s)
            .map<Object>((tok) =>
                v.isNumericKind(item) ? (num.tryParse(tok) ?? tok) : tok)
            .toList();
      default:
        return s;
    }
  }

  Widget _manualTable(HcTokens t, CfgField f) {
    final raw = _effective(f);
    final rows = raw is List
        ? List<Map<String, dynamic>>.from(
            raw.map((e) => Map<String, dynamic>.from(e as Map)))
        : <Map<String, dynamic>>[];
    final cols = f.itemFields ?? const [];
    void write() => _set(f.key!, rows);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labelBlock(t, f),
          SizedBox(height: t.space.sm),
          if (rows.isEmpty)
            Container(
              padding: EdgeInsets.all(t.space.lg),
              decoration: BoxDecoration(
                border: Border.all(color: t.stroke.hairline),
                borderRadius: BorderRadius.circular(t.radius.md),
              ),
              child: Text('No ${_plural(f)} yet — add one below.',
                  style: t.text.bodySmallStyle
                      .copyWith(color: t.surface.onBaseMuted)),
            ),
          for (var i = 0; i < rows.length; i++)
            Container(
              margin: EdgeInsets.only(bottom: t.space.sm),
              padding: EdgeInsets.all(t.space.md),
              decoration: BoxDecoration(
                color: t.surface.raised,
                borderRadius: BorderRadius.circular(t.radius.md),
                border: Border.all(color: t.stroke.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final c in cols)
                    if (!c.generated)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: t.space.xs),
                        child: Row(children: [
                          SizedBox(
                              width: 120,
                              child: Text(c.label ?? c.key ?? '',
                                  style: t.text.bodyStyle
                                      .copyWith(color: t.surface.onBaseMuted))),
                          Expanded(
                            child: c.readOnly
                                ? Text(
                                    rows[i][c.key] == null
                                        ? '—'
                                        : _columnInitial(c, rows[i][c.key]),
                                    style: t.text.bodyStyle.copyWith(
                                        color: t.surface.onBase,
                                        fontFeatures: const []))
                                // Same control set as a sourced table's columns,
                                // so an enum column (e.g. a device `kind`) renders
                                // as a dropdown instead of a free-text box you can
                                // typo into.
                                : _columnControl(
                                    t,
                                    c,
                                    _columnInitial(c, rows[i][c.key]),
                                    (s) {
                                      // Coerce to the column's type — a manual
                                      // table writes straight to the config
                                      // document, and an integration_id stored as
                                      // the string "19" fails to deserialize into
                                      // the u32 the plugin expects.
                                      rows[i][c.key!] = _coerceColumn(c, s);
                                      write();
                                    },
                                    key: ValueKey('${f.key}[$i].${c.key}'),
                                  ),
                          ),
                        ]),
                      ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: Icon(Icons.close, size: 16, color: t.accent.warn),
                      label: Text('Remove',
                          style: TextStyle(color: t.accent.warn)),
                      onPressed: () {
                        rows.removeAt(i);
                        write();
                      },
                    ),
                  ),
                ],
              ),
            ),
          _AddButton(
            label: 'Add ${_singular(f)}',
            onPressed: () {
              rows.add(newRowFor(cols));
              write();
            },
          ),
        ],
      ),
    );
  }

  Widget _note(HcTokens t, CfgField f) => Container(
        margin: EdgeInsets.symmetric(vertical: t.space.sm),
        padding: EdgeInsets.all(t.space.md),
        decoration: BoxDecoration(
          color: t.accent.active.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(t.radius.md),
          border: Border.all(color: t.accent.active.withValues(alpha: 0.3)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 18, color: t.accent.active),
          SizedBox(width: t.space.sm),
          Expanded(
            child: Text(f.noteText ?? '',
                style: t.text.bodyStyle.copyWith(color: t.surface.onBase)),
          ),
        ]),
      );

  Widget _saveBar(HcTokens t) {
    // Saving a bad value is worse than refusing to: the plugin restarts on
    // save, and a String where its config wants a number means it fails to
    // parse and drops offline entirely.
    final problems = _problems();
    final blocked = problems.isNotEmpty;
    return Container(
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.stroke.hairline)),
      ),
      child: Row(children: [
        if (blocked)
          Expanded(
            child: Text(
              problems.length == 1
                  ? problems.first
                  : '${problems.first}  (+${problems.length - 1} more)',
              style: t.text.bodySmallStyle.copyWith(color: t.accent.warn),
              overflow: TextOverflow.ellipsis,
            ),
          )
        else
          const Spacer(),
        SizedBox(width: t.space.md),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: t.accent.active,
              foregroundColor: t.surface.base,
              disabledBackgroundColor: t.stroke.hairline,
              disabledForegroundColor: t.surface.onBaseMuted),
          onPressed: widget.saving || blocked
              ? null
              : () => widget.onSave(_values, _sourceEdits),
          child: Text(widget.saving ? 'Saving…' : 'Save changes'),
        ),
      ]),
    );
  }

  // ── validation ────────────────────────────────────────────────────────────

  /// Everything wrong with the document right now, in operator language.
  ///
  /// The logic lives in `descriptor_validation.dart` so it can be tested
  /// without a widget — see `descriptor_validation_test.dart`.
  List<String> _problems() => v.documentProblems(
        descriptor: widget.descriptor,
        values: _values,
        defaults: _defaults,
        onlySectionId: widget.onlySectionId,
      );

  String? _validateScalar(CfgField f, String s) =>
      v.validateKind(f.kind, s, allowEmpty: !_isRequired(f));

  /// How a stored cell value reads in its control. A list joins back to the
  /// comma-separated form `_coerceColumn` parses; everything else stringifies.
  static String _columnInitial(CfgField c, Object? v) {
    if (v == null) return '';
    if (c.kind == 'list') {
      return v is List ? v.join(', ') : '$v';
    }
    return '$v';
  }

  static String? _placeholderFor(String? kind) {
    switch (kind) {
      case 'host':
      case 'ip':
        return '192.168.1.42';
      case 'url':
        return 'https://…';
      default:
        return null;
    }
  }

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> m) {
    Object? copy(Object? v) {
      if (v is Map) {
        return {for (final e in v.entries) e.key.toString(): copy(e.value)};
      }
      if (v is List) return [for (final e in v) copy(e)];
      return v;
    }

    return copy(m) as Map<String, dynamic>;
  }
}

// ── controls ────────────────────────────────────────────────────────────────

/// The segmented pill control — the LUX/RAW, C/F look, generalised.
/// Pick several values from a source-backed list — the control behind a `list`
/// column that declares a `source`.
///
/// The plain CSV box every other list column gets works mechanically, but it
/// asks the operator to know and retype raw device ids. A thermostat's sensors
/// are exactly that: references to devices owned by *other* plugins, which
/// nobody has memorised. Chips name what is chosen; the menu offers only what
/// is not chosen yet.
///
/// Values are emitted as CSV so `_coerceColumn` parses them back into a real
/// JSON array, the same as a typed list column.
class _MultiSelect extends StatelessWidget {
  const _MultiSelect({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.placeholder,
  });

  final List<CfgOption> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final remaining =
        options.where((o) => !selected.contains('${o.value}')).toList();

    // A stored id with no matching option means the device is gone (or belongs
    // to a plugin that is offline). Show the raw id rather than dropping the
    // chip — silently discarding it would edit the config by rendering it.
    String labelFor(String id) => options
        .firstWhere((o) => '${o.value}' == id,
            orElse: () => CfgOption(value: id, label: id))
        .label;

    return Wrap(
      spacing: t.space.xs,
      runSpacing: t.space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final id in selected)
          Container(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            decoration: BoxDecoration(
              color: t.surface.sunken,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: t.stroke.hairline),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(labelFor(id),
                  style: t.text.bodyStyle.copyWith(color: t.surface.onBase)),
              const SizedBox(width: 4),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged([...selected]..remove(id)),
                child:
                    Icon(Icons.close, size: 14, color: t.surface.onBaseMuted),
              ),
            ]),
          ),
        if (remaining.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: '',
            color: t.surface.overlay,
            position: PopupMenuPosition.under,
            itemBuilder: (_) => [
              for (final o in remaining)
                PopupMenuItem(
                  value: '${o.value}',
                  child: Text(o.label,
                      style: t.text.subtitleStyle
                          .copyWith(color: t.surface.onBase)),
                ),
            ],
            onSelected: (v) => onChanged([...selected, v]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: t.stroke.hairline),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, size: 14, color: t.accent.active),
                const SizedBox(width: 4),
                Text(placeholder ?? 'Add',
                    style: t.text.bodyStyle.copyWith(color: t.accent.active)),
              ]),
            ),
          )
        else if (selected.isEmpty)
          Text('Nothing available to choose.',
              style: t.text.bodySmallStyle.copyWith(
                  color: t.surface.onBaseMuted.withValues(alpha: 0.7))),
      ],
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented(
      {required this.options, required this.value, required this.onChanged});
  final List<CfgOption> options;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(o.value),
              child: AnimatedContainer(
                duration: t.motion.d(t.motion.fast),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color:
                      o.value == value ? t.accent.active : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(o.label,
                    style: t.text.bodyStyle.copyWith(
                        fontWeight: FontWeight.w500,
                        color: o.value == value
                            ? t.surface.base
                            : t.surface.onBaseMuted)),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onPressed});
  final String label;

  /// Null disables the button — an import in flight, for instance.
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: Icon(Icons.add, size: 18, color: t.accent.active),
        label: Text(label, style: TextStyle(color: t.accent.active)),
        onPressed: onPressed,
      ),
    );
  }
}

class _Input extends StatefulWidget {
  const _Input({
    super.key,
    required this.initial,
    required this.onChanged,
    this.onCommit,
    this.width,
    this.numeric = false,
    this.obscure = false,
    this.hint,
    this.placeholder,
    this.suffix,
    this.validate,
  });
  final String initial;
  final ValueChanged<String> onChanged;

  /// Fired on blur and on submit (not per keystroke). Live-resource fields use
  /// this to persist once the user is done editing, rather than on every char.
  final ValueChanged<String>? onCommit;
  final double? width;
  final bool numeric;
  final bool obscure;
  final String? hint;
  final String? placeholder;
  final String? suffix;
  final String? Function(String)? validate;

  @override
  State<_Input> createState() => _InputState();
}

class _InputState extends State<_Input> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChange);
  String? _error;
  String _committed = '';

  @override
  void initState() {
    super.initState();
    _committed = widget.initial;
  }

  void _commit() {
    if (widget.onCommit == null) return;
    if (_c.text == _committed) return;
    _committed = _c.text;
    widget.onCommit!(_c.text);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final field = TextField(
      controller: _c,
      focusNode: _focus,
      onSubmitted: (_) => _commit(),
      obscureText: widget.obscure,
      keyboardType: widget.numeric ? TextInputType.number : null,
      style: t.text.subtitleStyle.copyWith(color: t.surface.onBase),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint ?? widget.placeholder,
        hintStyle: t.text.bodyStyle
            .copyWith(color: t.surface.onBaseMuted.withValues(alpha: 0.6)),
        suffixText: widget.suffix,
        suffixStyle:
            t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: t.surface.sunken,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.radius.sm),
          borderSide: BorderSide(
              color: _error == null ? t.stroke.hairline : t.accent.warn),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.radius.sm),
          borderSide: BorderSide(
              color: _error == null ? t.accent.active : t.accent.warn),
        ),
      ),
      onChanged: (s) {
        setState(() => _error = widget.validate?.call(s));
        widget.onChanged(s);
      },
    );
    final boxed = widget.width == null
        ? field
        : SizedBox(width: widget.width, child: field);
    if (_error == null) return boxed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        boxed,
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(_error!,
              style: t.text.captionStyle.copyWith(color: t.accent.warn)),
        ),
      ],
    );
  }
}

/// A count-carrying toggle, for narrowing a long table to the rows that still
/// want something.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Material(
      color: selected
          ? t.accent.active.withValues(alpha: 0.16)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(t.radius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.radius.pill),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: t.space.sm, vertical: t.space.xs),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.radius.pill),
            border: Border.all(
                color: selected ? Colors.transparent : t.stroke.hairline),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: t.text.bodySmallStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected ? t.accent.active : t.surface.onBaseMuted)),
            SizedBox(width: t.space.xs),
            Text('$count',
                style: t.text.bodySmallStyle.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: selected ? t.accent.active : t.surface.onBaseMuted)),
          ]),
        ),
      ),
    );
  }
}

/// The row's headline state. Amber when it still wants a value, so a table of
/// freshly imported rows reads at a glance.
class _StateChip extends StatelessWidget {
  const _StateChip({required this.label, required this.attention});
  final String label;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: EdgeInsets.only(right: t.space.xs),
      padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: 2),
      decoration: BoxDecoration(
        color: attention
            ? t.accent.active.withValues(alpha: 0.16)
            : t.surface.overlay,
        borderRadius: BorderRadius.circular(t.radius.pill),
      ),
      child: Text(label,
          style: t.text.captionStyle.copyWith(
              fontWeight: FontWeight.w600,
              color: attention ? t.accent.active : t.surface.onBaseMuted)),
    );
  }
}

/// Apply one option to every selected row.
class _BulkSet extends StatelessWidget {
  const _BulkSet({
    required this.label,
    required this.options,
    required this.onPicked,
  });
  final String label;
  final List<CfgOption> options;
  final ValueChanged<Object?> onPicked;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return PopupMenuButton<Object?>(
      tooltip: label,
      onSelected: onPicked,
      itemBuilder: (_) => [
        for (final o in options)
          PopupMenuItem<Object?>(value: o.value, child: Text(o.label)),
      ],
      child: Container(
        padding:
            EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.xs),
        decoration: BoxDecoration(
          color: t.surface.raised,
          borderRadius: BorderRadius.circular(t.radius.sm),
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: t.text.bodySmallStyle.copyWith(
                  fontWeight: FontWeight.w600, color: t.surface.onBase)),
          Icon(Icons.arrow_drop_down, size: 16, color: t.surface.onBaseMuted),
        ]),
      ),
    );
  }
}
