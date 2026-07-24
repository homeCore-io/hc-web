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
        borderRadius: BorderRadius.circular(9),
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
    labelStyle: TextStyle(color: t.surface.onBaseMuted, fontSize: 13),
    floatingLabelStyle: TextStyle(color: t.accent.active, fontSize: 13),
    helperStyle: TextStyle(
        color: t.surface.onBaseMuted.withValues(alpha: 0.85), fontSize: 11),
    hintStyle: TextStyle(color: t.surface.onBaseMuted, fontSize: 13.5),
  );
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
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: color ?? t.surface.onBaseMuted,
      ),
    );
  }
}
