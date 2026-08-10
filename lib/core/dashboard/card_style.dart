import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';

/// How a card is drawn, as opposed to what it shows.
///
/// Phase 9 of `designer-plan.md` — "the things that stop a page reading as a
/// grid of boxes". A heading and a spacer already escape the box because their
/// *type* says so ([WidgetChrome]); this is the same escape offered to any
/// card, one at a time, by the person arranging the page.
///
/// **It lives in the widget's `config`.** There is no other field on the wire:
/// `DashboardWidget` is id, type, title, subtitle, refresh policy and config,
/// and adding a seventh would be a core change plus a plugin-visible ABI
/// change for a client-side drawing preference. Core reads only the keys each
/// widget type declares and stores the object verbatim, so a `style` key rides
/// along untouched — the same property that lets `heading` exist at all.
///
/// Absent means the default, and the default is the box. A page that has never
/// been styled must keep looking exactly as it does.
class CardStyle {
  const CardStyle({
    this.filled = true,
    this.bordered = true,
    this.titled = true,
    this.tint,
    this.blur = 0,
    this.corner,
    this.image,
    this.imageFit,
    this.imageOpacity = 1,
  });

  /// The card's own background, and the elevation that goes with it.
  final bool filled;

  /// The hairline around it.
  final bool bordered;

  /// The name band above the contents.
  ///
  /// Off is not the same as an empty name: an untitled card gives the band's
  /// height back to its contents, where a card named `""` still reserves it.
  /// A single device in a card called "One device" was the case that made this
  /// necessary — the band was the larger half of the card.
  final bool titled;

  /// Which colour the fill is, when there is one.
  ///
  /// Two tiers, and the pane says which is which — because hc-web's first
  /// design principle is that *a component never knows what it looks like; it
  /// reads `HcTokens` and a skin decides*, and a literal colour is a deliberate
  /// exception to it rather than an oversight.
  ///
  /// **Follows the skin**: a named surface level (`base`, `raised`, `sunken`,
  /// `overlay`) or a palette tint (`accent`, `danger`). Change skin and the
  /// card changes with it.
  ///
  /// **Fixed**: `#RRGGBB`. Identical under every skin, which is right for a
  /// photograph and wrong for a surface — a skin should not re-tint a picture
  /// of your living room, and should re-tint a panel.
  ///
  /// Null means the default surface, which is what every card had before.
  final String? tint;

  /// Frosts what is behind the card, 0–20.
  ///
  /// The machinery already existed for the Ambient Glass skin, where
  /// `HcSurface` reads `surface.glassBlur` and frosts its backdrop. This is the
  /// same capability offered per card on any skin.
  final double blur;

  /// A picture on the card, behind its contents.
  ///
  /// Independent of [filled]: an image *is* a fill, so a card can carry one
  /// with the colour turned off. A URL the browser can reach, resolved by the
  /// browser and never by core.
  final String? image;

  /// `cover` (fills and crops) or `contain` (shows all of it). The one choice
  /// nobody can guess from a preview and the one that is always wrong by
  /// default for half of the cases: a floor plan wants contain, a photo behind
  /// a room's controls wants cover.
  final String? imageFit;

  /// 0–1. The dial that decides whether the picture is the subject or the
  /// backdrop — at 1 it competes with the controls on top of it.
  final double imageOpacity;

  /// A step from the radius scale — `xs`, `sm`, `md`, `lg`, `pill` — never a
  /// pixel count. The ratchet exists because 132 literal corner radii once
  /// accumulated, and a style pane offering free pixels would be the 133rd.
  final String? corner;

  bool get isDefault =>
      filled &&
      bordered &&
      titled &&
      tint == null &&
      blur == 0 &&
      corner == null &&
      image == null &&
      imageFit == null &&
      imageOpacity == 1;

  static const key = 'style';

  factory CardStyle.fromConfig(Map<String, dynamic> config) {
    final raw = config[key];
    if (raw is! Map) return const CardStyle();
    // Anything that is not literally `false` is the default. A style written by
    // a newer client, or by hand, must not be able to blank a card by accident.
    return CardStyle(
      filled: raw['filled'] != false,
      bordered: raw['bordered'] != false,
      titled: raw['titled'] != false,
      tint: raw['tint'] is String ? raw['tint'] as String : null,
      // Clamped rather than trusted: a blur of 400 from a hand-edited document
      // would frost the whole page through one card.
      blur: raw['blur'] is num
          ? (raw['blur'] as num).toDouble().clamp(0.0, 20.0)
          : 0,
      corner: raw['corner'] is String ? raw['corner'] as String : null,
      image: raw['image'] is String ? raw['image'] as String : null,
      imageFit: raw['image_fit'] is String ? raw['image_fit'] as String : null,
      imageOpacity: raw['image_opacity'] is num
          ? (raw['image_opacity'] as num).toDouble().clamp(0.0, 1.0)
          : 1,
    );
  }

  /// [config] with this style applied.
  ///
  /// The default writes *nothing*, so styling a card and putting it back leaves
  /// the document byte-identical to one that was never touched — which is what
  /// keeps a page's JSON from accumulating a record of every idle click.
  Map<String, dynamic> toConfig(Map<String, dynamic> config) {
    final next = {...config};
    if (isDefault) {
      next.remove(key);
    } else {
      next[key] = {
        'filled': filled,
        'bordered': bordered,
        'titled': titled,
        // Only what differs from the default, so a card styled and put back
        // leaves the document as it found it.
        if (tint != null) 'tint': tint,
        if (blur > 0) 'blur': blur,
        if (corner != null) 'corner': corner,
        if (image != null) 'image': image,
        if (imageFit != null) 'image_fit': imageFit,
        if (imageOpacity != 1) 'image_opacity': imageOpacity,
      };
    }
    return next;
  }

  CardStyle copyWith({
    bool? filled,
    bool? bordered,
    bool? titled,
    Object? tint = _keep,
    double? blur,
    Object? corner = _keep,
    Object? image = _keep,
    Object? imageFit = _keep,
    double? imageOpacity,
  }) =>
      CardStyle(
        filled: filled ?? this.filled,
        bordered: bordered ?? this.bordered,
        titled: titled ?? this.titled,
        // `_keep` rather than null-means-keep, because "back to the default" is
        // a thing the pane has to be able to say.
        tint: identical(tint, _keep) ? this.tint : tint as String?,
        blur: blur ?? this.blur,
        corner: identical(corner, _keep) ? this.corner : corner as String?,
        image: identical(image, _keep) ? this.image : image as String?,
        imageFit:
            identical(imageFit, _keep) ? this.imageFit : imageFit as String?,
        imageOpacity: imageOpacity ?? this.imageOpacity,
      );

  @override
  bool operator ==(Object other) =>
      other is CardStyle &&
      other.filled == filled &&
      other.bordered == bordered &&
      other.titled == titled &&
      other.tint == tint &&
      other.blur == blur &&
      other.corner == corner &&
      other.image == image &&
      other.imageFit == imageFit &&
      other.imageOpacity == imageOpacity;

  @override
  int get hashCode => Object.hash(filled, bordered, titled, tint, blur, corner,
      image, imageFit, imageOpacity);
}

/// Distinguishes "leave it alone" from "set it back to null" in `copyWith`.
const Object _keep = Object();

/// The two tiers of fill, as the pane offers them.
///
/// Named surfaces and palette tints **follow the skin**; a literal colour does
/// not. Keeping them in one list with one label each is what lets the pane say
/// so in a sentence rather than in documentation nobody reads.
const cardTints = <({String key, String label, bool followsSkin})>[
  (key: 'raised', label: 'Card', followsSkin: true),
  (key: 'base', label: 'Page', followsSkin: true),
  (key: 'sunken', label: 'Recessed', followsSkin: true),
  (key: 'overlay', label: 'Overlay', followsSkin: true),
  (key: 'accent', label: 'Accent', followsSkin: true),
  (key: 'danger', label: 'Alert', followsSkin: true),
];

/// Corner steps, from the scale rather than from a pixel field.
const cardCorners = <({String key, String label})>[
  (key: 'xs', label: 'Sharp'),
  (key: 'sm', label: 'Slight'),
  (key: 'md', label: 'Card'),
  (key: 'lg', label: 'Round'),
  (key: 'pill', label: 'Pill'),
];

/// [tint] as a colour, or null for the surface the card would have had.
///
/// A palette tint is applied at low alpha over the card rather than at full
/// strength: an accent-coloured panel at 100% is a warning, not a surface, and
/// the accent budget is 3–5 placements per viewport — one card claiming the
/// whole accent would spend it all.
Color? resolveCardTint(HcTokens t, String? tint) => switch (tint) {
      null => null,
      'raised' => t.surface.raised,
      'base' => t.surface.base,
      'sunken' => t.surface.sunken,
      'overlay' => t.surface.overlay,
      'accent' => Color.alphaBlend(
          t.accent.active.withValues(alpha: 0.16), t.surface.raised),
      'danger' => Color.alphaBlend(
          t.accent.danger.withValues(alpha: 0.16), t.surface.raised),
      _ => _literal(tint),
    };

/// `#RRGGBB` / `#AARRGGBB`, or null when it is not one.
Color? _literal(String value) {
  var hex = value.trim();
  if (!hex.startsWith('#')) return null;
  hex = hex.substring(1);
  if (hex.length == 6) hex = 'ff$hex';
  if (hex.length != 8) return null;
  final n = int.tryParse(hex, radix: 16);
  return n == null ? null : Color(n);
}

/// [corner] as a radius, or null for the card's own.
double? resolveCardCorner(HcTokens t, String? corner) => switch (corner) {
      'xs' => t.radius.xs,
      'sm' => t.radius.sm,
      'md' => t.radius.md,
      'lg' => t.radius.lg,
      'pill' => t.radius.pill,
      _ => null,
    };

/// [style]'s picture as a decoration, or null when it has none.
///
/// A broken address costs the card its picture and nothing else — the
/// decoration simply fails to paint, and the contents are undisturbed. There is
/// no error state here on purpose: a card is where you read the house, not
/// where you debug a URL, and the address is checked where it is typed.
DecorationImage? cardDecorationImage(CardStyle style) {
  final url = style.image;
  if (url == null || url.trim().isEmpty) return null;
  return DecorationImage(
    image: NetworkImage(url),
    fit: switch (style.imageFit) {
      'contain' => BoxFit.contain,
      'fill' => BoxFit.fill,
      _ => BoxFit.cover,
    },
    opacity: style.imageOpacity.clamp(0.0, 1.0),
  );
}
