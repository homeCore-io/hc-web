import 'package:flutter/material.dart';

import '../../../design/components/hc_chip.dart';
import '../../../design/components/hc_dialog.dart';
import '../../../design/components/hc_sentence.dart';
import '../../../design/hc_icons.dart';
import '../../../design/tokens.dart';
import '../../../core/schema/attribute_policy.dart';
import '../../../core/schema/device_schema.dart';
import '../rhai.dart';
import 'device_choice_picker.dart';
import 'editor_style.dart';
import 'rule_refs.dart';

/// A `Conditional`'s predicate, as a sentence where it can be one.
///
/// Core stores this as a Rhai expression string — that is its actual shape — and
/// the editor rendered it as a labelled Material textarea containing
///
///     device_state("mode_night")["on"] == true
///
/// which was the single most form-like thing on the page, and said in code what
/// the rule says in English three lines above it.
///
/// So: the shape we understand becomes "the Night Mode is on", with the same
/// chips as every other condition. Anything else keeps its code, in a monospace
/// field, because the alternative is guessing — and the guard is stricter than
/// merely "can we parse it". We only offer chips when we can regenerate the
/// expression BYTE-FOR-BYTE. If a rule's spacing differs from ours, editing one
/// chip would silently reformat the whole predicate, and a reformat is a diff on
/// a rule that works.
class RhaiConditionField extends StatelessWidget {
  const RhaiConditionField({
    super.key,
    required this.source,
    required this.refs,
    required this.onChanged,
  });

  final String source;
  final RuleRefs refs;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    // A NEW if/else has no expression at all, and an empty string is not
    // round-trippable — so this fell straight through to the code box, and the
    // only way to start a branch was to know Rhai. Offer the same device
    // choice every other clause starts with.
    if (source.trim().isEmpty) {
      return _EmptyPredicate(refs: refs, onChanged: onChanged);
    }
    if (!isRoundTrippable(source)) {
      return _Code(source: source, onChanged: onChanged);
    }

    final c = parseRhai(source)!;
    final device = refs.deviceFor(c.deviceRef);
    final on = device != null && device.available && _isOn(device.state);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs),
      child: HcSentence(
        size: HcSentenceSize.small,
        parts: [
          'the',
          HcChip.device(
            label: refs.labelFor(c.deviceRef),
            on: on,
            tooltip: c.deviceRef,
            onTap: () => _editDevice(context, c),
          ),
          HcChip(
            label: _say(c, refs.schemaFor(c.deviceRef)?[c.attribute]),
            onTap: () => _editTest(context, c),
          ),
        ],
      ),
    );
  }

  static bool _isOn(Map<String, dynamic> s) =>
      s['on'] == true || s['open'] == true || s['motion'] == true;

  /// The comparison, in words. Reuses the same vocabulary as the AND IF rail, so
  /// a mode check reads identically whether it is a condition or a predicate.
  static String _say(RhaiCondition c, [AttributeSchema? schema]) {
    if (c.op == '==' || c.op == '!=') {
      final want = c.op == '==';
      if (c.value is bool) {
        final on = (c.value as bool) == want;
        // The plugin's own words where it declared them. This used to be a
        // private switch that hard-coded the conventions — including the one
        // hc-yolink and hc-isy contradict on `contact`.
        final states = boolStatesFor(c.attribute, schema);
        if (states != null) return 'is ${states[on].label}';
        return on ? 'is set' : 'is clear';
      }
      final attr = c.attribute.replaceAll('_', ' ');
      return want ? "'s $attr is ${c.value}" : "'s $attr is not ${c.value}";
    }

    final attr = c.attribute.replaceAll('_', ' ');
    final word = switch (c.op) {
      '>' => 'is above',
      '<' => 'is below',
      '>=' => 'is at least',
      '<=' => 'is at most',
      _ => c.op,
    };
    return "'s $attr $word ${c.value}";
  }

  Future<void> _editDevice(BuildContext context, RhaiCondition c) async {
    // The same searchable, room-grouped shell every other device choice uses.
    // This had its own flat list over every device — the third copy of the
    // problem, in the one place least likely to be found.
    final picked = await pickDeviceRef(
      context,
      refs: refs,
      current: c.deviceRef,
      kicker: 'If',
      title: 'Which device?',
    );
    if (picked != null) onChanged(emitRhai(c.copyWith(deviceRef: picked)));
  }

  Future<void> _editTest(BuildContext context, RhaiCondition c) async {
    final device = refs.deviceFor(c.deviceRef);
    // What this device actually reports, so the attribute is chosen rather
    // than typed. It used to be a free text field next to a "Value" box
    // hinted "true, false, a number, or text" — a form that asks you to know
    // the attribute is called `contact` and that it holds a bool.
    final known = refs.attributesOf(c.deviceRef);
    var attribute = c.attribute;
    var op = c.op;
    Object? value = c.value;
    final valCtrl = TextEditingController(text: '${c.value}');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final t = HcTokens.of(ctx);
          final schema = refs.schemaFor(c.deviceRef)?[attribute];
          final rows = (schema?.kind == AttributeKind.bool_ ||
                  device?.state[attribute] is bool)
              ? boolTransitionsFor(attribute, schema)
              : null;

          return HcDialog(
            title: 'Test',
            width: 420,
            actions: [
              HcButton(
                  label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
              HcButton(
                label: 'Done',
                kind: HcButtonKind.primary,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RailLabel('Attribute'),
                const SizedBox(height: 6),
                if (known.isEmpty)
                  TextFormField(
                    initialValue: attribute,
                    decoration: fieldDecoration(t),
                    onChanged: (v) => setInner(() => attribute = v.trim()),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: known.contains(attribute) ? attribute : null,
                    isExpanded: true,
                    decoration: fieldDecoration(t),
                    items: [
                      for (final a in known)
                        DropdownMenuItem(
                            value: a, child: Text(a.replaceAll('_', ' '))),
                    ],
                    onChanged: (v) => setInner(() {
                      attribute = v ?? attribute;
                      // The value belongs to the attribute it was chosen for.
                      value = null;
                      valCtrl.text = '';
                    }),
                  ),
                const SizedBox(height: 14),
                if (rows != null) ...[
                  // A boolean is two events; both get a name and neither
                  // needs a comparison operator to express.
                  const RailLabel('Is'),
                  const SizedBox(height: 6),
                  Row(children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: _Choice(
                          label: _sentenceCase(rows[i].state.label),
                          selected: value == rows[i].value,
                          onTap: () => setInner(() {
                            op = '==';
                            value = rows[i].value;
                          }),
                        ),
                      ),
                    ],
                  ]),
                ] else ...[
                  const RailLabel('Comparison'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: op,
                    decoration: fieldDecoration(t),
                    items: const [
                      DropdownMenuItem(value: '==', child: Text('is')),
                      DropdownMenuItem(value: '!=', child: Text('is not')),
                      DropdownMenuItem(value: '>', child: Text('is above')),
                      DropdownMenuItem(value: '<', child: Text('is below')),
                      DropdownMenuItem(value: '>=', child: Text('is at least')),
                      DropdownMenuItem(value: '<=', child: Text('is at most')),
                    ],
                    onChanged: (v) => setInner(() => op = v ?? op),
                  ),
                  const SizedBox(height: 14),
                  const RailLabel('Value'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: valCtrl,
                    decoration: fieldDecoration(
                      t,
                      hint: device?.state[attribute] == null
                          ? null
                          : 'currently ${device!.state[attribute]}',
                    ),
                    onChanged: (v) => value = _literal(v.trim()),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );

    if (ok == true && attribute.isNotEmpty) {
      onChanged(emitRhai(RhaiCondition(
        deviceRef: c.deviceRef,
        attribute: attribute,
        op: op,
        value: value ?? _literal(valCtrl.text.trim()),
      )));
    }
    valCtrl.dispose();
  }

  static String _sentenceCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static Object _literal(String raw) {
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    return num.tryParse(raw) ?? raw;
  }
}

/// The escape hatch. An expression we do not understand is shown as what it is.
class _Code extends StatefulWidget {
  const _Code({required this.source, required this.onChanged});

  final String source;
  final ValueChanged<String> onChanged;

  @override
  State<_Code> createState() => _CodeState();
}

class _CodeState extends State<_Code> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.source);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(HcIcons.lightning, size: 12, color: t.surface.onBaseMuted),
            SizedBox(width: t.space.xs),
            Text(
              'expression',
              style: t.text.captionStyle.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: t.surface.onBaseMuted),
            ),
          ],
        ),
        SizedBox(height: t.space.xs),
        TextField(
          controller: _ctrl,
          maxLines: null,
          style: t.text
              .resolve(t.text.bodySmall, mono: true)
              .copyWith(color: t.surface.onBase),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: t.surface.sunken,
            contentPadding: EdgeInsets.all(t.space.sm),
            border: OutlineInputBorder(
              borderRadius: t.radius.smR,
              borderSide: BorderSide(color: t.stroke.hairline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: t.radius.smR,
              borderSide: BorderSide(color: t.stroke.hairline),
            ),
          ),
          onChanged: widget.onChanged,
        ),
      ],
    );
  }
}

/// What a branch offers before it has a test.
///
/// A new if/else starts with an empty expression, which the round-trip guard
/// correctly refuses to render as chips — so it fell through to the code box,
/// and starting a branch meant knowing Rhai. This asks the same question every
/// other clause opens with: which device?
///
/// Picking one seeds `device_state("ref")["attr"] == true` against the most
/// telling attribute the device has, which is immediately editable as chips.
/// The predicate a branch most often wants is "is this thing on/open", and
/// starting there is closer than starting at a blank line.
class _EmptyPredicate extends StatelessWidget {
  const _EmptyPredicate({required this.refs, required this.onChanged});

  final RuleRefs refs;
  final ValueChanged<String> onChanged;

  /// The attribute to open on: the first boolean the device reports, in the
  /// order someone would think of them.
  static String _seedAttribute(Map<String, dynamic> state) {
    const preferred = [
      'on',
      'open',
      'contact',
      'motion',
      'occupancy',
      'locked',
      'leak'
    ];
    for (final name in preferred) {
      if (state[name] is bool) return name;
    }
    for (final e in state.entries) {
      if (e.value is bool) return e.key;
    }
    // Nothing boolean: `state` is the next most likely thing to test, and the
    // chips let it be changed in one tap.
    return state.keys.isEmpty ? 'on' : state.keys.first;
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs),
      child: Row(children: [
        HcChip.device(
          label: 'pick a device',
          on: false,
          onTap: () async {
            final picked = await pickDeviceRef(
              context,
              refs: refs,
              kicker: 'If',
              title: 'Which device?',
            );
            if (picked == null) return;
            final device = refs.deviceFor(picked);
            final attribute = _seedAttribute(device?.state ?? const {});
            final seed = device?.state[attribute];
            onChanged(emitRhai(RhaiCondition(
              deviceRef: picked,
              attribute: attribute,
              op: '==',
              // Seed with the state it is NOT in, so the branch reads as
              // something that can happen rather than as already true.
              value: seed is bool ? !seed : true,
            )));
          },
        ),
        SizedBox(width: t.space.sm),
        TextButton(
          onPressed: () => onChanged(' '),
          child: Text('Write an expression',
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted)),
        ),
      ]),
    );
  }
}

/// One of a boolean attribute's two states, as a choice rather than a value
/// you have to know how to spell.
class _Choice extends StatelessWidget {
  const _Choice({
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
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
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
