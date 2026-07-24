import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/models/device_state.dart';
import '../../../core/rules/schema.dart';
import '../../../design/tokens.dart';
import 'editor_style.dart';
import 'rule_refs.dart';

/// Renders every field of a node from its [HcVariant] descriptor.
///
/// Nothing here knows what a `SetDeviceState` is. Adding a variant to
/// `schema.dart` gives it a working form for free — which is the only way a
/// 34-action vocabulary stays maintainable.
///
/// Recursive fields (nested conditions and action lists) are *not* drawn here;
/// the tree widgets own those, because they need to nest their own chrome.
class NodeFields extends StatelessWidget {
  const NodeFields({
    super.key,
    required this.variant,
    required this.fields,
    required this.refs,
    required this.onChanged,
  });

  final HcVariant variant;
  final Map<String, Object?> fields;
  final RuleRefs refs;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scalar = variant.fields.where((f) => !f.isRecursive).toList();
    if (scalar.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in scalar)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FieldEditor(
              field: f,
              value: fields[f.name],
              refs: refs,
              // A device reference elsewhere on this node lets the attribute
              // field suggest that device's actual attributes.
              siblingDeviceRef: _siblingDeviceRef(),
              onChanged: (v) {
                if (v == null && !f.required) {
                  fields.remove(f.name);
                } else {
                  fields[f.name] = v;
                }
                onChanged();
              },
            ),
          ),
      ],
    );
  }

  String? _siblingDeviceRef() {
    final v = fields['device_id'];
    return v is String && v.isNotEmpty ? v : null;
  }
}

/// A single field, dispatched on its [HcFieldKind].
class FieldEditor extends StatelessWidget {
  const FieldEditor({
    super.key,
    required this.field,
    required this.value,
    required this.refs,
    required this.onChanged,
    this.siblingDeviceRef,
  });

  final HcField field;
  final Object? value;
  final RuleRefs refs;
  final ValueChanged<Object?> onChanged;
  final String? siblingDeviceRef;

  String get _label => field.label ?? _humanize(field.name);

  @override
  Widget build(BuildContext context) {
    final options = enumValuesFor(field.kind);
    if (options != null) return _enumField(context, options);

    return switch (field.kind) {
      HcFieldKind.deviceRef => _deviceField(context),
      HcFieldKind.deviceRefList => _deviceListField(context),
      HcFieldKind.attribute => _attributeField(context),
      HcFieldKind.modeRef => _pickField(context, refs.modes),
      HcFieldKind.sceneRef => _pickField(context, refs.scenes),
      HcFieldKind.boolean => _boolField(context),
      HcFieldKind.integer || HcFieldKind.number => _numberField(context),
      HcFieldKind.time => _timeField(context),
      HcFieldKind.weekdays => _weekdayField(context),
      HcFieldKind.json => _jsonField(context),
      HcFieldKind.script => _textField(context, lines: 3, mono: true),
      _ => _textField(context),
    };
  }

  // -- primitives ----------------------------------------------------------

  InputDecoration _dec(BuildContext context, {String? hint}) => fieldDecoration(
        HcTokens.of(context),
        label: _label + (field.required ? '' : ' (optional)'),
        help: field.help,
        hint: hint,
      );

  Widget _textField(BuildContext context, {int lines = 1, bool mono = false}) =>
      TextFormField(
        initialValue: value?.toString() ?? '',
        decoration: _dec(context),
        maxLines: lines,
        style: mono ? const TextStyle(fontFamily: 'monospace') : null,
        onChanged: (v) => onChanged(v.isEmpty ? null : v),
      );

  Widget _numberField(BuildContext context) => TextFormField(
        initialValue: value?.toString() ?? '',
        decoration: _dec(context),
        keyboardType: TextInputType.number,
        onChanged: (v) {
          if (v.isEmpty) return onChanged(null);
          final parsed = field.kind == HcFieldKind.integer
              ? int.tryParse(v)
              : num.tryParse(v);
          if (parsed != null) onChanged(parsed);
        },
      );

  Widget _boolField(BuildContext context) => Row(
        children: [
          Expanded(child: Text(_label)),
          // Tri-state: an optional bool must be able to go back to "unset",
          // which is not the same as false. `to: false` fires on turn-off;
          // omitting `to` fires on any change.
          if (!field.required)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.backspace_outlined, size: 16),
              onPressed: value == null ? null : () => onChanged(null),
            ),
          Switch(
            value: value == true,
            onChanged: onChanged,
          ),
        ],
      );

  Widget _enumField(BuildContext context, List<String> options) =>
      DropdownButtonFormField<String>(
        initialValue: options.contains(value) ? value as String : null,
        decoration: _dec(context),
        items: [
          if (!field.required)
            const DropdownMenuItem(value: null, child: Text('—')),
          for (final o in options)
            DropdownMenuItem(value: o, child: Text(_humanize(o))),
        ],
        onChanged: onChanged,
      );

  // -- references ----------------------------------------------------------

  Widget _deviceField(BuildContext context) {
    final current = value as String?;
    final missing =
        current != null && current.isNotEmpty && !refs.isKnownDevice(current);

    // A device can be referenced two ways — by `device_id`
    // (`yolink_d88b4c0400064299`) or by `canonical_name`
    // (`bathroom.bathroom_door_sensor`) — and core accepts either. Existing rules
    // are written with raw ids, while `refFor` prefers the canonical name, so
    // keying every item on `refFor` left nothing matching the stored value and
    // the dropdown rendered blank on *every* rule.
    //
    // So the item for the currently-referenced device is keyed on the form this
    // rule actually stores. That fixes the display, and it means saving a rule
    // you did not retarget leaves its reference byte-for-byte as it was, rather
    // than silently rewriting device_id into canonical_name.
    String valueFor(DeviceState d) =>
        (current != null && (d.id == current || d.canonicalName == current))
            ? current
            : refs.refFor(d);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: refs.isKnownDevice(current ?? '') ? current : null,
          isExpanded: true,
          decoration: _dec(context, hint: 'Pick a device'),
          items: [
            if (!field.required)
              const DropdownMenuItem(value: null, child: Text('— any —')),
            for (final d in refs.devices)
              DropdownMenuItem(
                value: valueFor(d),
                child: Text(
                  d.name?.isNotEmpty ?? false ? d.name! : d.id,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
        // Core rewrites references to deleted devices as `DELETED:` and
        // disables the rule. Say so plainly instead of showing a blank box.
        if (missing)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              current.startsWith('DELETED:')
                  ? 'This device was deleted — pick a replacement.'
                  : 'Unknown device "$current" — it may be offline or removed.',
              style: TextStyle(
                fontSize: 11,
                color: HcTokens.of(context).accent.danger,
              ),
            ),
          ),
      ],
    );
  }

  Widget _deviceListField(BuildContext context) {
    final list = [
      for (final v in (value as List? ?? const [])) '$v',
    ];

    final t = HcTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RailLabel(_label),
        if (field.help != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(field.help!,
                style: TextStyle(fontSize: 11.5, color: t.surface.onBaseMuted)),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final ref in list)
              InputChip(
                label: Text(refs.labelFor(ref)),
                onDeleted: () => onChanged(
                  [...list]..remove(ref),
                ),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('Add'),
              onPressed: () async {
                final picked = await _pickDevice(context);
                if (picked != null && !list.contains(picked)) {
                  onChanged([...list, picked]);
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Future<String?> _pickDevice(BuildContext context) {
    final t = HcTokens.of(context);
    // A Material Dialog + ListTile: the tokenised surface reads studio, and
    // ListTile's own hit-testing is the reliable one for a long tap list.
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: t.surface.overlay,
        child: SizedBox(
          width: 460,
          height: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Add a device',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: t.surface.onBase)),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final d in refs.devices)
                      ListTile(
                        dense: true,
                        title: Text(
                            d.name?.isNotEmpty ?? false ? d.name! : d.id,
                            style: TextStyle(
                                color: t.surface.onBase, fontSize: 14)),
                        subtitle: Text(refs.refFor(d),
                            style: TextStyle(
                                color: t.surface.onBaseMuted, fontSize: 12)),
                        onTap: () => Navigator.pop(ctx, refs.refFor(d)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attributeField(BuildContext context) {
    final known = siblingDeviceRef == null
        ? const <String>[]
        : refs.attributesOf(siblingDeviceRef!);

    // Free text, because a device may not be reporting the attribute yet — but
    // offer what it *is* reporting so nobody has to guess at `color_temp`.
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: value?.toString() ?? ''),
      optionsBuilder: (t) => known.where(
        (a) => a.toLowerCase().contains(t.text.toLowerCase()),
      ),
      onSelected: onChanged,
      fieldViewBuilder: (context, controller, focus, _) => TextFormField(
        controller: controller,
        focusNode: focus,
        decoration: _dec(
          context,
          hint: known.isEmpty ? null : 'e.g. ${known.first}',
        ),
        onChanged: (v) => onChanged(v.isEmpty ? null : v),
      ),
    );
  }

  Widget _pickField(
    BuildContext context,
    List<({String id, String name})> options,
  ) =>
      DropdownButtonFormField<String>(
        initialValue:
            options.any((o) => o.id == value) ? value as String : null,
        isExpanded: true,
        decoration: _dec(context),
        items: [
          if (!field.required)
            const DropdownMenuItem(value: null, child: Text('— any —')),
          for (final o in options)
            DropdownMenuItem(value: o.id, child: Text(o.name)),
        ],
        onChanged: onChanged,
      );

  // -- time ----------------------------------------------------------------

  Widget _timeField(BuildContext context) {
    final text = value?.toString() ?? '00:00:00';
    final parts = text.split(':');
    final h = int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 0;
    final m = int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0;

    return InputDecorator(
      decoration: _dec(context),
      child: Row(
        children: [
          Text(
            '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
          ),
          const Spacer(),
          TextButton(
            onPressed: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: h, minute: m),
              );
              if (picked == null) return;
              // Seconds are always zero: the scheduler ticks once a minute and
              // compares only hour and minute, so offering seconds would be a
              // control that silently does nothing.
              onChanged('${picked.hour.toString().padLeft(2, '0')}:'
                  '${picked.minute.toString().padLeft(2, '0')}:00');
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Widget _weekdayField(BuildContext context) {
    const all = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final selected = {
      for (final d in (value as List? ?? const [])) '$d',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RailLabel(_label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          children: [
            for (final d in all)
              FilterChip(
                label: Text(d, style: const TextStyle(fontSize: 11)),
                selected: selected.contains(d),
                visualDensity: VisualDensity.compact,
                onSelected: (on) {
                  final next = {...selected};
                  if (on) {
                    next.add(d);
                  } else {
                    next.remove(d);
                  }
                  // Keep calendar order, not click order.
                  onChanged([
                    for (final x in all)
                      if (next.contains(x)) x
                  ]);
                },
              ),
          ],
        ),
      ],
    );
  }

  // -- json ----------------------------------------------------------------

  Widget _jsonField(BuildContext context) => _JsonField(
        label: _dec(context),
        value: value,
        onChanged: onChanged,
      );
}

/// A JSON field that refuses to hand invalid JSON to the rule.
///
/// It keeps the user's raw text while they type — reformatting mid-edit is
/// maddening — and only writes back when the text parses.
class _JsonField extends StatefulWidget {
  const _JsonField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final InputDecoration label;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  State<_JsonField> createState() => _JsonFieldState();
}

class _JsonFieldState extends State<_JsonField> {
  late final TextEditingController _c =
      TextEditingController(text: _encode(widget.value));
  String? _error;

  static String _encode(Object? v) {
    if (v == null) return '';
    if (v is String) return jsonEncode(v);
    return jsonEncode(v);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        maxLines: null,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        decoration: widget.label.copyWith(
          errorText: _error,
          hintText: '{"on": true}',
        ),
        onChanged: (text) {
          if (text.trim().isEmpty) {
            setState(() => _error = null);
            return widget.onChanged(null);
          }
          try {
            final parsed = jsonDecode(text);
            setState(() => _error = null);
            widget.onChanged(parsed);
          } on FormatException {
            // Hold the last good value; surface the problem without destroying
            // what they're typing.
            setState(() => _error = 'Not valid JSON');
          }
        },
      );
}

String _humanize(String raw) {
  if (raw.isEmpty) return raw;
  // device_id → Device id;  CrossesAbove → Crosses above
  final spaced = raw
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ')
      .toLowerCase();
  return spaced[0].toUpperCase() + spaced.substring(1);
}

extension<T> on List<T> {
  T? elementAtOrNull(int i) => i >= 0 && i < length ? this[i] : null;
}
