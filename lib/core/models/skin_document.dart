import 'package:flutter/material.dart';

import '../../design/skin_seeds.dart';

/// A skin as core stores it — the wire form of `hc_types::skin::Skin`.
///
/// Step 4 of `theme-editor-plan.md`. Separate from [SkinSeeds] on purpose:
/// this is a *document*, with an id, a name and a parent, and it is what
/// crosses the network. `SkinSeeds` is the design decision set that the
/// derivation consumes. Collapsing them would put transport concerns —
/// hex strings, unknown enum names, absent fields — inside the thing every
/// token is computed from.
///
/// **Parsing never throws.** A malformed skin is a skin that falls back to its
/// [base] built-in, and a client that threw here would take the whole app down
/// over one bad colour in one row of a list. [toSeeds] returns null instead,
/// and the caller falls back.
@immutable
class SkinDocument {
  const SkinDocument({
    required this.id,
    required this.name,
    required this.base,
    required this.seeds,
    this.overrides = const {},
  });

  final String id;
  final String name;

  /// Which built-in this was forked from — and where it falls back to.
  final String base;

  /// The raw seed map, exactly as core returned it. Kept unparsed so a field
  /// this build does not understand survives an edit-and-save round trip
  /// rather than being dropped on the floor.
  final Map<String, dynamic> seeds;

  /// Token path to colour, e.g. `accent.warn`.
  final Map<String, String> overrides;

  /// Never throws, whatever arrives.
  ///
  /// `as Map?` is a *cast*, and a cast of a String throws — so a `seeds` field
  /// that arrived as anything but an object used to take the app down at parse
  /// time, before the fallback chain it was written for could run. Found by the
  /// sweep in `skin_resolve_test.dart` rather than by reading, which is the
  /// argument for the sweep.
  factory SkinDocument.fromJson(Map<String, dynamic> json) {
    final rawSeeds = json['seeds'];
    final rawOverrides = json['overrides'];
    return SkinDocument(
      id: json['id'] is String ? json['id'] as String : '',
      name: json['name'] is String ? json['name'] as String : '',
      base: json['base'] is String ? json['base'] as String : 'midnight',
      seeds: rawSeeds is Map
          ? Map<String, dynamic>.from(rawSeeds)
          : const <String, dynamic>{},
      overrides: rawOverrides is Map
          ? {for (final e in rawOverrides.entries) '${e.key}': '${e.value}'}
          : const <String, String>{},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'base': base,
        'seeds': seeds,
        if (overrides.isNotEmpty) 'overrides': overrides,
      };

  /// The seed set this document describes, or null if it cannot be read.
  ///
  /// Null is the signal to fall back to [base]. Every failure lands here —
  /// a missing field, a colour that is not a colour, an enum name from a
  /// later version — because the caller's response to all of them is the same
  /// and distinguishing them would only mean more ways to crash.
  SkinSeeds? toSeeds() {
    try {
      Color colour(String key) {
        final raw = seeds[key];
        if (raw is! String) throw FormatException('$key is missing');
        return _parseHex(raw);
      }

      Color? maybeColour(String key) {
        final raw = seeds[key];
        return raw is String ? _parseHex(raw) : null;
      }

      double number(String key) {
        final raw = seeds[key];
        if (raw is num) return raw.toDouble();
        throw FormatException('$key is not a number');
      }

      final corners = (seeds['corners'] as List?) ?? const [];
      if (corners.length != 4) {
        throw const FormatException('corners must have four values');
      }

      return SkinSeeds(
        name: id,
        brightness: switch (seeds['brightness']) {
          'light' => Brightness.light,
          'dark' => Brightness.dark,
          _ => throw const FormatException('brightness must be dark or light'),
        },
        ground: colour('ground'),
        raised: colour('raised'),
        sunken: colour('sunken'),
        overlay: colour('overlay'),
        ink: colour('ink'),
        inkMuted: colour('ink_muted'),
        accent: colour('accent'),
        onAccent: colour('on_accent'),
        active: colour('active'),
        inactive: colour('inactive'),
        success: colour('success'),
        warn: colour('warn'),
        danger: colour('danger'),
        offline: colour('offline'),
        hairline: colour('hairline'),
        focus: maybeColour('focus'),
        corners: (
          (corners[0] as num).toDouble(),
          (corners[1] as num).toDouble(),
          (corners[2] as num).toDouble(),
          (corners[3] as num).toDouble(),
        ),
        spaceUnit: number('space_unit'),
        typeScale: number('type_scale'),
        glowStrength: number('glow_strength'),
        glowRadius: number('glow_radius'),
        density: switch (seeds['density']) {
          'compact' => SkinDensity.compact,
          'comfortable' => SkinDensity.comfortable,
          'wall' => SkinDensity.wall,
          _ => throw const FormatException('unknown density'),
        },
        motion: switch (seeds['motion']) {
          'crisp' => SkinMotion.crisp,
          'standard' => SkinMotion.standard,
          'calm' => SkinMotion.calm,
          _ => throw const FormatException('unknown motion'),
        },
        glass: switch (seeds['glass']) {
          'tinted' => SkinGlass.tinted,
          'frosted' => SkinGlass.frosted,
          // Absent is `none` — core defaults it, and a skin written before the
          // glass split simply has no opinion.
          null || 'none' => SkinGlass.none,
          _ => throw const FormatException('unknown glass'),
        },
      );
    } catch (_) {
      return null;
    }
  }
}

/// `#RRGGBB` or `#AARRGGBB` — the two forms core accepts.
Color _parseHex(String value) {
  final hex = value.startsWith('#') ? value.substring(1) : value;
  if (hex.length != 6 && hex.length != 8) {
    throw FormatException('$value is not a colour');
  }
  final n = int.parse(hex, radix: 16);
  return Color(hex.length == 6 ? 0xFF000000 | n : n);
}

/// Parses a colour, or null. Public because applying overrides needs it and a
/// second copy of the same parser is how the two would drift.
Color? parseSkinColour(String value) {
  try {
    return _parseHex(value);
  } catch (_) {
    return null;
  }
}
