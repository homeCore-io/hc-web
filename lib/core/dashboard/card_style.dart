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
  const CardStyle({this.filled = true, this.bordered = true});

  /// The card's own background, and the elevation that goes with it.
  final bool filled;

  /// The hairline around it.
  final bool bordered;

  bool get isDefault => filled && bordered;

  static const key = 'style';

  factory CardStyle.fromConfig(Map<String, dynamic> config) {
    final raw = config[key];
    if (raw is! Map) return const CardStyle();
    // Anything that is not literally `false` is the default. A style written by
    // a newer client, or by hand, must not be able to blank a card by accident.
    return CardStyle(
      filled: raw['filled'] != false,
      bordered: raw['bordered'] != false,
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
      next[key] = {'filled': filled, 'bordered': bordered};
    }
    return next;
  }

  CardStyle copyWith({bool? filled, bool? bordered}) => CardStyle(
        filled: filled ?? this.filled,
        bordered: bordered ?? this.bordered,
      );

  @override
  bool operator ==(Object other) =>
      other is CardStyle &&
      other.filled == filled &&
      other.bordered == bordered;

  @override
  int get hashCode => Object.hash(filled, bordered);
}
