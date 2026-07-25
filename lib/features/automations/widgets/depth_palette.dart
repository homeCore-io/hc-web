import 'package:flutter/material.dart';

/// The colours that carry nesting depth and clause, shared by the tree and the
/// outline so both panes describe the same rule in the same terms.
///
/// **Okabe–Ito, not a hand-picked set.** The previous palette ran blue → teal →
/// amber → pink → violet, which is four hues that collapse in pairs under the
/// common colour-vision deficiencies: teal against blue for deuteranopia,
/// amber against pink for protanopia. Okabe–Ito is designed to stay distinct
/// under all three types, and the order here also alternates light and dark so
/// adjacent levels differ in *value* as well as hue — which is what keeps them
/// apart in greyscale, at low contrast, and on a dim kitchen tablet.
///
/// Colour is never the only signal in either pane: depth is also indentation,
/// clause is also a word, and a disabled step is also struck through. That is
/// deliberate — this palette makes the redundant signal legible, it does not
/// carry meaning alone.
const kDepthColors = [
  Color(0xFF56B4E9), // sky blue
  Color(0xFFE69F00), // orange
  Color(0xFF009E73), // bluish green
  Color(0xFFCC79A7), // reddish purple
  Color(0xFF0072B2), // blue
  Color(0xFFD55E00), // vermillion
];

Color depthColor(int depth) => kDepthColors[depth % kDepthColors.length];
