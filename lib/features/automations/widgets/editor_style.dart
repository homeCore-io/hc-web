import 'package:flutter/material.dart';

import '../../../design/tokens.dart';

/// Studio styling shared across the rule editor's body — one place so the token
/// look of a field or a rail label is defined once, not copied into node_trees,
/// field_editors and rhai_condition.

/// A filled, hairline-bordered input in the house palette. Replaces the Material
/// `OutlineInputBorder` decorations the generated field forms used to carry, so a
/// text/number/expression box reads like the rest of the app, not a web form.
InputDecoration fieldDecoration(
  HcTokens t, {
  String? label,
  String? help,
  String? hint,
}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: t.radius.smR,
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    labelText: label,
    helperText: help,
    helperMaxLines: 3,
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: t.surface.sunken,
    border: border(t.stroke.hairline),
    enabledBorder: border(t.stroke.hairline),
    focusedBorder: border(t.accent.active, 1.5),
    labelStyle: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted),
    floatingLabelStyle: t.text.bodyStyle.copyWith(color: t.accent.active),
    helperStyle: t.text.captionStyle
        .copyWith(color: t.surface.onBaseMuted.withValues(alpha: 0.85)),
    hintStyle: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted),
  );
}

/// One tappable row in an `HcDialog` picker — the add-node palette and the two
/// device pickers all share this, so a list row reads the same wherever a rule is
/// edited: a title, an optional muted subtitle, and a soft accent wash when it is
/// the current selection. Replaces the Material `ListTile` those pickers used to
/// carry.
class PickerRow extends StatelessWidget {
  const PickerRow({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.selected = false,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Material(
      color: selected
          ? t.accent.active.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: t.radius.smR,
      child: InkWell(
        onTap: onTap,
        borderRadius: t.radius.smR,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: t.text.subtitleStyle.copyWith(
                    color: selected ? t.accent.active : t.surface.onBase),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: t.text.bodySmallStyle
                      .copyWith(color: t.surface.onBaseMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A small uppercase structural label — "AND", "THEN", "ELSE", "ELSE IF", the
/// nested-list titles. Muted by default; a branch can pass its depth colour.
class RailLabel extends StatelessWidget {
  const RailLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Text(
      text.toUpperCase(),
      style: t.text.captionStyle.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: color ?? t.surface.onBaseMuted),
    );
  }
}
