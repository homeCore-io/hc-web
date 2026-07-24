import 'package:flutter/material.dart';

import '../../../design/components/hc_chip.dart';
import '../../../design/components/hc_dialog.dart';
import '../../../design/components/hc_sentence.dart';
import '../../../design/hc_icons.dart';
import '../../../design/tokens.dart';
import '../rhai.dart';
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
            label: _say(c),
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
  static String _say(RhaiCondition c) {
    if (c.op == '==' || c.op == '!=') {
      final want = c.op == '==';
      if (c.value is bool) {
        final on = (c.value as bool) == want;
        return switch (c.attribute) {
          'on' => on ? 'is on' : 'is off',
          'open' => on ? 'is open' : 'is closed',
          'locked' => on ? 'is locked' : 'is unlocked',
          'motion' => on ? 'detects motion' : 'detects no motion',
          _ => on ? 'is set' : 'is clear',
        };
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
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => _DevicePicker(refs: refs, current: c.deviceRef),
    );
    if (picked != null) onChanged(emitRhai(c.copyWith(deviceRef: picked)));
  }

  Future<void> _editTest(BuildContext context, RhaiCondition c) async {
    final attrCtrl = TextEditingController(text: c.attribute);
    final valCtrl = TextEditingController(text: '${c.value}');
    var op = c.op;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final t = HcTokens.of(ctx);
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
              children: [
                TextField(
                  controller: attrCtrl,
                  decoration: fieldDecoration(t, label: 'Attribute'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: op,
                  decoration: fieldDecoration(t, label: 'Comparison'),
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
                const SizedBox(height: 12),
                TextField(
                  controller: valCtrl,
                  decoration: fieldDecoration(t,
                      label: 'Value', help: 'true, false, a number, or text'),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (ok == true) {
      onChanged(emitRhai(RhaiCondition(
        deviceRef: c.deviceRef,
        attribute: attrCtrl.text.trim(),
        op: op,
        value: _literal(valCtrl.text.trim()),
      )));
    }
    attrCtrl.dispose();
    valCtrl.dispose();
  }

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
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: t.surface.onBaseMuted,
              ),
            ),
          ],
        ),
        SizedBox(height: t.space.xs),
        TextField(
          controller: _ctrl,
          maxLines: null,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.5,
            color: t.surface.onBase,
          ),
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

class _DevicePicker extends StatelessWidget {
  const _DevicePicker({required this.refs, required this.current});

  final RuleRefs refs;
  final String current;

  @override
  Widget build(BuildContext context) {
    final devices = refs.devices;

    return HcDialog(
      title: 'Device',
      width: 460,
      child: SizedBox(
        height: 440,
        child: ListView(
          children: [
            for (final d in devices)
              PickerRow(
                selected: d.id == current || d.canonicalName == current,
                title: d.displayName,
                subtitle: d.canonicalName ?? d.id,
                // Give back the SAME form of reference the rule already used, so
                // a rule keyed on canonical names stays keyed on canonical names.
                onTap: () => Navigator.pop(
                  context,
                  current.contains('.') ? (d.canonicalName ?? d.id) : d.id,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
