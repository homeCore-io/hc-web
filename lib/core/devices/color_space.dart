/// sRGB ↔ CIE 1931 xy, the colour space Hue and most colour bulbs accept.
///
/// One implementation, because there were two: the device sheet's and the rule
/// editor's, identical but for what they returned for pure black. Two matrices
/// that must be exact inverses of each other are not something to keep in two
/// files.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The D65 white point — what an undefined chromaticity resolves to.
///
/// `(0, 0)` is not a colour: it is off the spectral locus entirely, and a
/// bridge handed it will clamp or reject. White is the honest answer for "this
/// colour has no chromaticity".
const _d65 = (0.3127, 0.3290);

double _linear(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

(double, double) rgbToXy(Color c) {
  final r = _linear(c.r), g = _linear(c.g), b = _linear(c.b);
  final x = r * 0.4124 + g * 0.3576 + b * 0.1805;
  final y = r * 0.2126 + g * 0.7152 + b * 0.0722;
  final z = r * 0.0193 + g * 0.1192 + b * 0.9505;

  final sum = x + y + z;
  if (sum == 0) return _d65;

  return (
    (x / sum * 10000).round() / 10000,
    (y / sum * 10000).round() / 10000,
  );
}

/// CIE 1931 xy → sRGB, for showing a swatch.
///
/// Uses the sRGB/D65 matrix, which is the exact inverse of the one [rgbToXy]
/// uses. Pairing Hue's Wide-RGB matrix with sRGB's — an easy mistake, since both
/// are published as "the" conversion — makes the round trip drift by ~0.07 in x,
/// which is a visibly different colour.
Color xyToRgb(double x, double y) {
  if (y <= 0) return const Color(0xFF000000);

  const luminance = 1.0;
  final z = 1.0 - x - y;
  final bigX = (luminance / y) * x;
  final bigZ = (luminance / y) * z;

  var r = bigX * 3.2406 - luminance * 1.5372 - bigZ * 0.4986;
  var g = -bigX * 0.9689 + luminance * 1.8758 + bigZ * 0.0415;
  var b = bigX * 0.0557 - luminance * 0.2040 + bigZ * 1.0570;

  // Normalise before gamma: an out-of-gamut xy can exceed 1 in a channel, and
  // clamping first would shift the hue rather than just its brightness.
  final peak = [r, g, b].reduce(math.max);
  if (peak > 1) {
    r /= peak;
    g /= peak;
    b /= peak;
  }

  double gamma(double c) {
    final v = c.clamp(0.0, 1.0);
    return v <= 0.0031308
        ? 12.92 * v
        : 1.055 * math.pow(v, 1 / 2.4).toDouble() - 0.055;
  }

  return Color.fromARGB(
    255,
    (gamma(r) * 255).round(),
    (gamma(g) * 255).round(),
    (gamma(b) * 255).round(),
  );
}
