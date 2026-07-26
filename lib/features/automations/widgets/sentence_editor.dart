import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/rules/node.dart';
import '../../../core/rules/schema.dart';
import '../../../design/components/hc_chip.dart';
import '../../../design/components/hc_sentence.dart';
import '../../../design/tokens.dart';
import '../rule_phrasing.dart';
import 'field_editors.dart';
import 'rule_refs.dart';

/// One node, said out loud.
///
/// Renders a [Phrase] as prose with editable chips, and tucks everything the
/// sentence *doesn't* say behind a "Refine" disclosure. That disclosure is the
/// entire fix for the old editor's worst habit: nine labelled boxes, six of them
/// empty and optional, every one given the same weight as the two that matter.
///
/// A node that nests — `Conditional`, `Or`, `Parallel` — has no sentence, because
/// prose stops scaling about two levels deep. Those fall through to the tree.
class SentenceNode extends StatefulWidget {
  const SentenceNode({
    super.key,
    required this.node,
    required this.variant,
    required this.phrase,
    required this.refs,
    required this.onChanged,
    this.size = HcSentenceSize.normal,
    this.trailing,
  });

  final HcNode node;
  final HcVariant variant;
  final Phrase phrase;
  final RuleRefs refs;
  final VoidCallback onChanged;
  final HcSentenceSize size;
  final Widget? trailing;

  @override
  State<SentenceNode> createState() => _SentenceNodeState();
}

class _SentenceNodeState extends State<SentenceNode> {
  bool _refining = false;
  bool _hover = false;
  bool _advancedOpen = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final hidden = refinements(widget.variant, widget.phrase);
    final set =
        hidden.where((f) => _isNoteworthy(f, widget.node[f.name])).length;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _sentence(context)),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
          if (widget.phrase.summary != null) ...[
            SizedBox(height: t.space.sm),
            Text(
              widget.phrase.summary!,
              style: TextStyle(
                fontSize: 12,
                color: t.surface.onBaseMuted,
                fontFeatures: t.numericFontFeatures,
              ),
            ),
          ],
          // The disclosure appears when it has something to TELL you — a hidden
          // field holding a non-default value — and otherwise only when you reach
          // for it. Every action carries a required `track_event_value: false`, so
          // showing it unconditionally printed "Refine — track event value" on
          // every single row of every single rule. A control that is always there
          // saying nothing is just noise wearing a label.
          if (hidden.isNotEmpty && (set > 0 || _hover || _refining)) ...[
            SizedBox(height: t.space.sm),
            GestureDetector(
              onTap: () => setState(() => _refining = !_refining),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _refining ? Icons.expand_less : Icons.add,
                    size: 14,
                    color: t.surface.onBaseMuted,
                  ),
                  SizedBox(width: t.space.xs),
                  Text(
                    // Say what's in there, and say when some of it is *set* — a
                    // collapsed field that quietly holds a value is a trap.
                    _refining
                        ? 'Hide refinements'
                        : set > 0
                            ? 'Refine · $set set'
                            : 'Refine — ${_names(hidden)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: set > 0 ? t.accent.primary : t.surface.onBaseMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_refining) ...[
            SizedBox(height: t.space.sm),
            Container(
              padding: EdgeInsets.all(t.space.md),
              decoration: BoxDecoration(
                color: t.surface.sunken,
                borderRadius: t.radius.smR,
                border: Border.all(color: t.stroke.hairline),
              ),
              child: Column(
                children: [
                  for (final f in hidden)
                    Padding(
                      padding: EdgeInsets.only(bottom: t.space.sm),
                      child: FieldEditor(
                        field: f,
                        value: widget.node[f.name],
                        refs: widget.refs,
                        siblingDeviceRef: widget.node['device_id'] as String?,
                        siblingAttribute: widget.node['attribute'] as String?,
                        onChanged: (v) {
                          if (v == null && !f.required) {
                            widget.node.fields.remove(f.name);
                          } else {
                            widget.node[f.name] = v;
                          }
                          widget.onChanged();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Whether a hidden field holding [value] is worth warning about.
  ///
  /// The "· N set" badge exists to catch a collapsed field that quietly holds a
  /// value. A *required* field sitting at its own default is not that: every
  /// `SetDeviceState` carries `track_event_value: false`, so counting it made
  /// all three actions of a working rule read "Refine · 1 set" forever — a
  /// warning that fires always is a warning you learn to ignore.
  static bool _isNoteworthy(HcField field, Object? value) {
    if (value == null) return false;
    if (field.defaultValue == null) return true;
    // Values here are JSON-shaped (a `state` payload is a Map), so compare them
    // structurally rather than by identity.
    return jsonEncode(value) != jsonEncode(field.defaultValue);
  }

  static String _names(List<HcField> fs) {
    final names = fs.take(3).map((f) => f.name.replaceAll('_', ' ')).join(', ');
    return fs.length > 3 ? '$names…' : names;
  }

  Widget _sentence(BuildContext context) => HcSentence(
        size: widget.size,
        parts: [
          for (final part in widget.phrase.parts)
            if (part is String)
              part
            else if (part is Slot)
              _chip(context, part),
        ],
      );

  Widget _chip(BuildContext context, Slot slot) {
    final field =
        widget.variant.fields.where((f) => f.name == slot.field).firstOrNull;
    final value = widget.node[slot.field];

    // A verb slot shows what the rule *does*, not what it stores: "closes", not
    // `false`. It usually stands for more than one field, and tapping it must
    // reach all of them.
    if (slot.verb != null) {
      final owned = [
        for (final name in slot.fields)
          if (widget.variant.fields.where((f) => f.name == name).firstOrNull
              case final f?)
            f,
      ];
      return HcChip(
        label: slot.verb!(value),
        onTap: owned.isEmpty ? null : () => _editAll(context, owned),
      );
    }

    if (field?.kind == HcFieldKind.deviceRef) {
      // A slot that owns `device_ids` speaks EVERY device the node watches, one
      // chip each. It used to render only `device_id` — so a rule watching four
      // door sensors said "the Dining Room Door Sensor opens" and buried the
      // other three behind a disclosure. Four chips is longer than one; being
      // right is worth the width.
      final owned = [
        for (final name in slot.fields)
          if (widget.variant.fields.where((f) => f.name == name).firstOrNull
              case final f?)
            f,
      ];
      final refs = slot.alsoEdits.contains('device_ids')
          ? devicesOf(widget.node)
          : (value is String ? [value] : const <String>[]);

      if (refs.isEmpty) {
        return HcChip.device(
          label: 'pick a device',
          on: false,
          onTap: field == null ? null : () => _editAll(context, owned),
        );
      }

      return Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < refs.length; i++) ...[
            if (i > 0 && i == refs.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text('or',
                    style: TextStyle(
                        fontSize: 13,
                        color: HcTokens.of(context).surface.onBaseMuted)),
              ),
            Builder(builder: (context) {
              final device = widget.refs.deviceFor(refs[i]);
              return HcChip.device(
                label: widget.refs.labelFor(refs[i]),
                // The chip carries the device's LIVE state. This is what makes a
                // rule show you the house rather than merely its own config.
                on: device != null && device.available && _isOn(device.state),
                tooltip: refs[i],
                onTap: owned.isEmpty ? null : () => _editAll(context, owned),
              );
            }),
          ],
        ],
      );
    }

    return HcChip.value(
      label: _render(value, field),
      onTap: field == null ? null : () => _edit(context, field),
    );
  }

  static bool _isOn(Map<String, dynamic> s) =>
      s['on'] == true || s['open'] == true || s['motion'] == true;

  String _render(Object? v, HcField? f) {
    if (v == null) {
      return f == null ? '…' : 'set ${f.name.replaceAll('_', ' ')}';
    }
    if (v is List) return v.isEmpty ? '…' : v.join(', ');
    return '$v';
  }

  /// Editing happens in place: tap the chip, get exactly the field it speaks.
  Future<void> _edit(BuildContext context, HcField field) =>
      _editAll(context, [field]);

  /// Which of a verb slot's fields the sheet leads with.
  ///
  /// A verb chip usually owns three fields — `attribute`, `op`, `value` — and
  /// showing all three gave equal weight to the answer and to the machinery.
  /// "Opens / Closes" is the question; `attribute: open` and `Op: Eq` are how
  /// it is stored, and a new user reading "Eq" learns nothing they wanted.
  ///
  /// So the value leads and the mechanism goes behind a disclosure. It stays
  /// reachable because retargeting the attribute is a real thing to want — it
  /// is just not the common thing.
  static const _mechanism = {'attribute', 'op', 'change_kind'};

  static List<HcField> _leading(List<HcField> fields) {
    final lead = fields.where((f) => !_mechanism.contains(f.name)).toList();
    // A slot made ENTIRELY of mechanism has nothing to lead with, and hiding
    // everything would open an empty sheet.
    return lead.isEmpty ? fields : lead;
  }

  Future<void> _editAll(BuildContext context, List<HcField> fields) async {
    final t = HcTokens.of(context);
    final lead = _leading(fields);
    final advanced = fields.where((f) => !lead.contains(f)).toList();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: t.surface.overlay,
        title: Text(
          fields.length == 1
              ? (fields.single.label ?? fields.single.name.replaceAll('_', ' '))
              : 'Edit',
        ),
        content: SizedBox(
          width: 420,
          child: StatefulBuilder(
            builder: (context, setInner) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final field in [
                  ...lead,
                  if (_advancedOpen) ...advanced,
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FieldEditor(
                      field: field,
                      value: widget.node[field.name],
                      refs: widget.refs,
                      siblingDeviceRef: widget.node['device_id'] as String?,
                      siblingAttribute: widget.node['attribute'] as String?,
                      onChanged: (v) {
                        if (v == null && !field.required) {
                          widget.node.fields.remove(field.name);
                        } else {
                          widget.node[field.name] = v;
                        }
                        setInner(() {});
                        widget.onChanged();
                        setState(() {});
                      },
                    ),
                  ),
                if (advanced.isNotEmpty)
                  InkWell(
                    onTap: () => setInner(() {
                      _advancedOpen = !_advancedOpen;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          _advancedOpen
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 16,
                          color: t.surface.onBaseMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _advancedOpen
                              ? 'Hide advanced'
                              : 'Advanced — ${_names(advanced)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: t.surface.onBaseMuted,
                          ),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _advancedOpen = false;
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

/// Renders a node as a sentence when it has a phrase, and falls through to the
/// generic form otherwise.
///
/// Not every one of 34 actions earns bespoke prose — `PublishMqtt` is a topic and
/// a payload and always will be. The generic form is a legitimate answer, not a
/// failure, and mixing the two in one rule is fine because the chips are
/// identical either way.
class NodeBody extends StatelessWidget {
  const NodeBody({
    super.key,
    required this.node,
    required this.registry,
    required this.refs,
    required this.onChanged,
    required this.phraseFor,
    this.size = HcSentenceSize.normal,
    this.trailing,
  });

  final HcNode node;
  final Map<String, HcVariant> registry;
  final RuleRefs refs;
  final VoidCallback onChanged;
  final Phrase? Function(HcNode) phraseFor;
  final HcSentenceSize size;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final variant = registry[node.tag];
    if (variant == null) {
      return Text('Unsupported: ${node.tag}',
          style: TextStyle(color: HcTokens.of(context).accent.danger));
    }

    final phrase = phraseFor(node);
    if (phrase == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                variant.label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          NodeFields(
            variant: variant,
            fields: node.fields,
            refs: refs,
            onChanged: onChanged,
          ),
        ],
      );
    }

    return SentenceNode(
      node: node,
      variant: variant,
      phrase: phrase,
      refs: refs,
      onChanged: onChanged,
      size: size,
      trailing: trailing,
    );
  }
}


/// Test seam for the leading/advanced split.
///
/// The split is a pure decision about a field list, and worth testing without
/// pumping a dialog and tapping through it.
abstract final class SentenceNodeTestAccess {
  static List<HcField> leading(List<HcField> fields) =>
      _SentenceNodeState._leading(fields);
}
