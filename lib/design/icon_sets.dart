import 'package:flutter/widgets.dart';

import '../core/devices/presentation.dart';
import 'hc_icons.dart';

/// Which glyphs the house wears.
///
/// John: *"icon sets should be configurable to allow users to choose
/// additional icon sets."*
///
/// The app's icon vocabulary is not a list of icon names — it is
/// **facet → glyph**. Every icon a device wears is chosen by what the device
/// *is* (`HcIcons.forFacet`), which is why a per-device override could name a
/// facet rather than an icon. So an icon set is an alternative answer to that
/// same question, and swapping one is swapping the answer, not the question.
///
/// That is what makes this possible without a mapping file: a set has to cover
/// thirty-odd facets and nothing else. A general "install any icon font" would
/// need a name→codepoint table per font, which is metadata no font carries and
/// nobody wants to type.
abstract class IconSet {
  const IconSet();

  /// Stored on the skin, so it must be stable.
  String get key;

  /// What the picker shows.
  String get label;

  /// The glyph for [facet]. [on] asks for the filled weight where the set has
  /// one; a set with a single weight returns the same glyph, which reads as
  /// "this set does not distinguish" rather than as a missing icon.
  IconData forFacet(DeviceFacet facet, {bool on = false});
}

/// The set the app has always drawn. Two weights, and `on` really does fill.
class PhosphorIconSet extends IconSet {
  const PhosphorIconSet();

  @override
  String get key => 'phosphor';

  @override
  String get label => 'Phosphor';

  // Delegates rather than restating: the mapping is ninety-two codepoints in
  // one switch, and a second copy of it would be ninety-two chances to
  // transcribe one wrong. `hc_icons.dart` documents that its codepoints are
  // verified by rasterising the font, never guessed — that verification should
  // not have to happen twice.
  @override
  IconData forFacet(DeviceFacet facet, {bool on = false}) =>
      HcIcons.phosphorFacet(facet, on: on);
}

/// Material's own, which the app already carries for card and menu icons.
///
/// A real second choice rather than a demonstration: it is heavier and rounder
/// than Phosphor, it is already bundled, and a wall panel across a dim room is
/// a legitimate reason to want the heavier one.
class MaterialIconSet extends IconSet {
  const MaterialIconSet();

  @override
  String get key => 'material';

  @override
  String get label => 'Material';

  // The mapping already exists on the facet itself, where it has been used by
  // the device panel and the card library all along.
  @override
  IconData forFacet(DeviceFacet facet, {bool on = false}) => facet.icon;
}

/// The sets in force, and the one that is.
///
/// A global, like [FontRegistry], and for the same reason: `HcIcons.forFacet`
/// is a static reached from everywhere, including places with no
/// `BuildContext`. Threading a set through every call site would be a large
/// refactor of the most-used function in the design system to express
/// something that is genuinely one value for the whole app.
class IconSets {
  IconSets._();

  static const builtIn = <IconSet>[PhosphorIconSet(), MaterialIconSet()];

  static IconSet _active = _defaultSet;
  static IconSet get active => _active;

  /// Bumped when the set changes, so the app repaints. Same shape as the font
  /// registry's, and for the same reason — this is read outside the build that
  /// chose it.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// Chooses by key.
  ///
  /// Null and unknown resolve the same way — to the default set — and that is
  /// deliberate. "Keep whatever was active" was the first version and it is
  /// wrong twice over: switching to a skin with no choice would silently
  /// inherit the previous skin's icons, and the result would depend on which
  /// skins you had looked at first. Falling back to Phosphor is not falling
  /// back to blank; it is the set the app has always drawn.
  static void select(String? key) {
    final next = builtIn.where((s) => s.key == key).firstOrNull ?? _defaultSet;
    if (next.key == _active.key) return;
    _active = next;
    revision.value++;
  }

  static const _defaultSet = PhosphorIconSet();

  /// Visible for tests.
  static void reset() {
    _active = _defaultSet;
    revision.value = 0;
  }
}

/// The override key a skin stores its choice under.
const iconSetOverrideKey = 'icons.set';
