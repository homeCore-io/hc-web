import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/devices/presentation.dart';
import '../../../core/rules/schema.dart';
import '../../../core/schema/attribute_policy.dart';
import '../../../core/schema/device_schema.dart';
import '../../../design/tokens.dart';
import 'device_choice_picker.dart';
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
              siblingAttribute: fields['attribute'] as String?,
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
    this.siblingAttribute,
  });

  final HcField field;
  final Object? value;
  final RuleRefs refs;
  final ValueChanged<Object?> onChanged;
  final String? siblingDeviceRef;

  /// The attribute this node is watching, when another field on it names one.
  ///
  /// A value field (`to`, `from`) is only meaningful against an attribute: it
  /// is what turns an untyped JSON box into "Opens / Closes".
  final String? siblingAttribute;

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
      // A value field naming a boolean attribute is a choice between that
      // attribute's two states — not a JSON box that expects you to know the
      // attribute is a bool and to type `true`. `to` is declared `json`
      // because it accepts any shape; when we can tell the shape, we should.
      HcFieldKind.json when _boolStates != null => _boolStateField(context),
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
    final t = HcTokens.of(context);
    final device = current == null ? null : refs.deviceFor(current);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RailLabel(_label + (field.required ? '' : ' (optional)')),
        const SizedBox(height: 6),
        // Opens the same searchable, room-grouped shell the "add a node" flows
        // use. It was a DropdownButtonFormField over every device the hub
        // knows: no search, no rooms, no live state, registration order — a
        // full-height list of everything on any real house.
        InkWell(
          onTap: () async {
            final picked = await pickDeviceRef(
              context,
              refs: refs,
              current: current,
              kicker: _label,
            );
            if (picked != null) onChanged(picked);
          },
          borderRadius: t.radius.smR,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: t.surface.sunken,
              borderRadius: t.radius.smR,
              border: Border.all(
                color: missing ? t.accent.danger : t.stroke.hairline,
              ),
            ),
            child: Row(children: [
              Icon(
                device == null
                    ? Icons.help_outline
                    : facetOf(device, device.schema).icon,
                size: 17,
                color: t.surface.onBaseMuted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current == null || current.isEmpty
                          ? 'Pick a device'
                          : refs.labelFor(current),
                      overflow: TextOverflow.ellipsis,
                      style: t.text.subtitleStyle.copyWith(
                          color: current == null || current.isEmpty
                              ? t.surface.onBaseMuted
                              : t.surface.onBase),
                    ),
                    // The stored reference stays visible: two devices can share
                    // a display name, and the rule is written against this.
                    if (device != null)
                      Text(
                        device.canonicalName ?? device.id,
                        overflow: TextOverflow.ellipsis,
                        style: t.text
                            .resolve(t.text.caption, mono: true)
                            .copyWith(color: t.surface.onBaseMuted),
                      ),
                  ],
                ),
              ),
              if (!field.required && current != null && current.isNotEmpty)
                IconButton(
                  tooltip: 'Any device',
                  icon: const Icon(Icons.backspace_outlined, size: 15),
                  onPressed: () => onChanged(null),
                ),
              Icon(Icons.unfold_more, size: 16, color: t.surface.onBaseMuted),
            ]),
          ),
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
              style: t.text.captionStyle.copyWith(color: t.accent.danger),
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
                style:
                    t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
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

  Future<String?> _pickDevice(BuildContext context) => pickDeviceRef(
        context,
        refs: refs,
        kicker: _label,
        title: 'Add a device',
      );

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
    final t = HcTokens.of(context);
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
            style: t.text.resolve(t.text.title, mono: true),
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
    final t = HcTokens.of(context);
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
                label: Text(d, style: t.text.captionStyle),
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

  // -- boolean states ------------------------------------------------------

  /// The two named states of the attribute this value field is about, or null
  /// when it is not about a boolean one.
  List<({bool value, StateLabel state})>? get _boolStates {
    final device = siblingDeviceRef;
    final attribute = siblingAttribute;
    if (device == null || attribute == null || attribute.isEmpty) return null;
    final schema = refs.schemaFor(device)?[attribute];
    // The schema is asked first and the live reading second: an attribute a
    // plugin declared `bool` is boolean even on a device that has not reported
    // it yet, which is the case an observed-value check gets wrong.
    if (schema?.kind != AttributeKind.bool_ &&
        refs.deviceFor(device)?.state[attribute] is! bool) {
      return null;
    }
    return boolTransitionsFor(attribute, schema);
  }

  /// Both directions of a boolean attribute, named by the plugin where it
  /// declared them and by the client lexicon where it did not.
  Widget _boolStateField(BuildContext context) {
    final t = HcTokens.of(context);
    final rows = _boolStates!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RailLabel(_label),
        const SizedBox(height: 6),
        Row(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: _StateChoice(
                label: _sentenceCase(rows[i].state.transition),
                selected: value == rows[i].value,
                onTap: () => onChanged(rows[i].value),
              ),
            ),
          ],
          // Optional means "fires on any change", which is not the same as
          // either direction and must stay reachable.
          if (!field.required) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Any change',
              icon: const Icon(Icons.backspace_outlined, size: 16),
              onPressed: value == null ? null : () => onChanged(null),
            ),
          ],
        ]),
        if (value == null && !field.required)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Fires on any change.',
                style:
                    t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
          ),
      ],
    );
  }

  static String _sentenceCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

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
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return TextField(
      controller: _c,
      maxLines: null,
      style: t.text.resolve(t.text.body, mono: true),
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

/// One of a boolean attribute's two named states.
///
/// A pair of these replaces the JSON box on a value field: the plugin says a
/// door "opens" and "closes", so those are the words, and neither direction
/// needs a Not gate to reach.
class _StateChoice extends StatelessWidget {
  const _StateChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final accent = t.accent.active;
    return Material(
      color: selected ? accent.withValues(alpha: 0.14) : t.surface.raised,
      borderRadius: t.radius.smR,
      child: InkWell(
        onTap: onTap,
        borderRadius: t.radius.smR,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: t.radius.smR,
            border: Border.all(
              color: selected ? accent : t.stroke.hairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: t.text.bodyStyle.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? t.surface.onBase : t.surface.onBaseMuted),
          ),
        ),
      ),
    );
  }
}
