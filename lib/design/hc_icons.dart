import 'package:flutter/widgets.dart';

import '../core/devices/presentation.dart';

/// The icon vocabulary — Phosphor, driven straight off its fonts.
///
/// Phosphor rather than Material for one property that outweighs taste: it has a
/// **weight axis**. The same glyph is an outline when a device is off and a solid
/// when it is on, so state lives in the icon's own form and not only in its
/// colour. Single-weight sets (Lucide, Tabler) force colour to carry the whole
/// burden, and Material's set is a large part of what makes a Flutter app *look*
/// like a Flutter app.
///
/// We bundle the two fonts and address the codepoints ourselves rather than
/// depending on `phosphor_flutter`, because that package does not compile on
/// Flutter 3.44: `IconData` became a `final class`, and it declares
/// `PhosphorIconData extends IconData`. Using the fonts directly costs two
/// asset files and keeps the property we chose Phosphor for. Icons are MIT
/// (see assets/fonts/PHOSPHOR-LICENSE).
///
/// Every device icon resolves through [forFacet], so it is a function of what a
/// device *is* — never of which plugin happens to own it.
class HcIcons {
  HcIcons._();

  static const _regular = 'Phosphor';
  static const _fill = 'PhosphorFill';

  /// The icon for a device, in the weight its state calls for.
  ///
  /// [on] is what flips outline → fill. That is the entire point: a lit lamp is
  /// the same glyph as a dark one, solid.
  static IconData forFacet(DeviceFacet facet, {bool on = false}) =>
      switch (facet) {
        DeviceFacet.light ||
        DeviceFacet.dimmableLight ||
        DeviceFacet.colorLight =>
          on
              ? const IconData(0xe2dc, fontFamily: _fill)
              : const IconData(0xe2dc, fontFamily: _regular),
        DeviceFacet.outlet => on
            ? const IconData(0xe946, fontFamily: _fill)
            : const IconData(0xe946, fontFamily: _regular),
        DeviceFacet.switch_ => on
            ? const IconData(0xe676, fontFamily: _fill)
            : const IconData(0xe676, fontFamily: _regular),
        // Phosphor has no blind/shade glyph; `rows` reads as horizontal slats,
        // which is the closest honest match.
        DeviceFacet.cover => on
            ? const IconData(0xe5a2, fontFamily: _fill)
            : const IconData(0xe5a2, fontFamily: _regular),
        // A lock is the exception to the weight rule. "Unlocked" is not a
        // *stronger* locked — it is a different thing, and a filled padlock would
        // read as "extra locked". So the glyph changes, not the weight.
        DeviceFacet.lock => on
            ? const IconData(0xe306, fontFamily: _fill)
            : const IconData(0xe2fa, fontFamily: _regular),
        DeviceFacet.door => on
            ? const IconData(0xe61c, fontFamily: _fill)
            : const IconData(0xe61c, fontFamily: _regular),
        DeviceFacet.window => on
            ? const IconData(0xeaf8, fontFamily: _fill)
            : const IconData(0xeaf8, fontFamily: _regular),
        DeviceFacet.garage => on
            ? const IconData(0xecd6, fontFamily: _fill)
            : const IconData(0xecd6, fontFamily: _regular),
        DeviceFacet.motion || DeviceFacet.occupancy => on
            ? const IconData(0xe73a, fontFamily: _fill)
            : const IconData(0xe73a, fontFamily: _regular),
        DeviceFacet.contact => on
            ? const IconData(0xe7e6, fontFamily: _fill)
            : const IconData(0xe7e6, fontFamily: _regular),
        DeviceFacet.temperature => on
            ? const IconData(0xe5cc, fontFamily: _fill)
            : const IconData(0xe5cc, fontFamily: _regular),
        DeviceFacet.humidity => on
            ? const IconData(0xe210, fontFamily: _fill)
            : const IconData(0xe210, fontFamily: _regular),
        DeviceFacet.illuminance => on
            ? const IconData(0xe472, fontFamily: _fill)
            : const IconData(0xe472, fontFamily: _regular),
        DeviceFacet.power => on
            ? const IconData(0xe2de, fontFamily: _fill)
            : const IconData(0xe2de, fontFamily: _regular),
        DeviceFacet.smoke => on
            ? const IconData(0xe624, fontFamily: _fill)
            : const IconData(0xe624, fontFamily: _regular),
        DeviceFacet.water => on
            ? const IconData(0xe566, fontFamily: _fill)
            : const IconData(0xe566, fontFamily: _regular),
        DeviceFacet.vibration => on
            ? const IconData(0xe802, fontFamily: _fill)
            : const IconData(0xe802, fontFamily: _regular),
        DeviceFacet.climate => on
            ? const IconData(0xe5c6, fontFamily: _fill)
            : const IconData(0xe5c6, fontFamily: _regular),
        DeviceFacet.mediaPlayer => on
            ? const IconData(0xea08, fontFamily: _fill)
            : const IconData(0xea08, fontFamily: _regular),
        DeviceFacet.scene => on
            ? const IconData(0xe6a2, fontFamily: _fill)
            : const IconData(0xe6a2, fontFamily: _regular),
        DeviceFacet.button => on
            ? const IconData(0xe192, fontFamily: _fill)
            : const IconData(0xe192, fontFamily: _regular),
        DeviceFacet.timer => on
            ? const IconData(0xe492, fontFamily: _fill)
            : const IconData(0xe492, fontFamily: _regular),
        DeviceFacet.siren => on
            ? const IconData(0xe9b8, fontFamily: _fill)
            : const IconData(0xe9b8, fontFamily: _regular),
        DeviceFacet.sensor => on
            ? const IconData(0xe628, fontFamily: _fill)
            : const IconData(0xe628, fontFamily: _regular),
        DeviceFacet.unknown => on
            ? const IconData(0xe3e8, fontFamily: _fill)
            : const IconData(0xe3e8, fontFamily: _regular),
      };

  // -- fixed roles ---------------------------------------------------------

  static const camera = IconData(0xe4da, fontFamily: _regular);
  static const security = IconData(0xe40c, fontFamily: _regular);
  static const warning = IconData(0xe4e0, fontFamily: _fill);
  static const battery = IconData(0xe0c8, fontFamily: _fill);
  static const offline = IconData(0xeb5a, fontFamily: _regular);
  static const search = IconData(0xe30c, fontFamily: _regular);
  static const grip = IconData(0xeae2, fontFamily: _fill);

  // media transport — always filled; a transport control is a button, not a state
  static const play = IconData(0xe3d0, fontFamily: _fill);
  static const pause = IconData(0xe39e, fontFamily: _fill);
  static const next = IconData(0xe5a6, fontFamily: _fill);
  static const previous = IconData(0xe5a4, fontFamily: _fill);
  static const volume = IconData(0xe44a, fontFamily: _regular);

  // navigation
  static const dashboards = IconData(0xe464, fontFamily: _regular);
  static const devices = IconData(0xeba4, fontFamily: _regular);
  static const automations = IconData(0xe6ec, fontFamily: _regular);
  static const scenes = IconData(0xe8c2, fontFamily: _regular);
  static const modes = IconData(0xe434, fontFamily: _regular);
  static const events = IconData(0xe000, fontFamily: _regular);
  static const admin = IconData(0xe5d4, fontFamily: _regular);
  static const plugins = IconData(0xe596, fontFamily: _regular);
}
