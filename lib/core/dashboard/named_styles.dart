/// The library of saved looks, which is not stored anywhere.
///
/// A named style is nine properties and a name, and applying one **copies**
/// them onto a card — John: *"styles like templates should be applied and then
/// able to be customized. That is the whole point of a custom designer"*. So
/// there is nothing to keep in step, nothing to re-sync, and no question about
/// what happens to a card when the style it was made from changes. It changes
/// nothing. It cannot.
///
/// **Which means the library needs no storage.** A style exists exactly as long
/// as some card is wearing it, so the list of saved looks is *derived*: every
/// distinct name on every page you can see. Defining a style is naming a card;
/// forgetting one is renaming the last card that wore it. Orphans cannot
/// happen and there is nothing to clean up.
///
/// That is `groups.dart`'s argument about paths, and it holds here for the same
/// reason — a registry is only worth its cost when something has to outlive its
/// last member, and neither of these does.
///
/// **What a style is not.** It carries no device, no title, no position and no
/// size, because [CardStyle] has no field for any of them: pointing a toggle at
/// a different light is an edit to that toggle and reaches nothing else, at any
/// distance, forever. Nothing here can change that — there is no wiring in a
/// look to change.
library;

import '../models/dashboard.dart';
import 'card_style.dart';

/// A saved look, and where it is already being worn.
///
/// [uses] is what makes the picker readable rather than a list of words: a
/// style used on four cards across two pages is a house style, and one used
/// once is something you named a minute ago and may have finished with.
typedef NamedStyle = ({String name, CardStyle style, int uses});

/// Every named look on [dashboards], most-used first.
///
/// **The first card wins a disagreement.** Two cards can wear the same name and
/// differ — one of them was edited afterwards, which is not only allowed but
/// the entire point of applying rather than linking. So this reports *a* style
/// for the name rather than pretending there is a canonical one, and takes the
/// most common spelling: the odd one out is somebody's deliberate change and
/// should not redefine the thing it was made from.
List<NamedStyle> namedStylesIn(Iterable<DashboardDefinition> dashboards) {
  // Counted per distinct style so the winner is the *commonest* arrangement
  // rather than whichever page happened to load first.
  final tally = <String, Map<CardStyle, int>>{};
  for (final dashboard in dashboards) {
    for (final widget in dashboard.widgets) {
      final style = CardStyle.fromConfig(widget.config);
      final name = style.name;
      if (name == null) continue;
      final byStyle = tally.putIfAbsent(name, () => {});
      byStyle[style] = (byStyle[style] ?? 0) + 1;
    }
  }

  final styles = <NamedStyle>[
    for (final entry in tally.entries)
      () {
        var best = entry.value.entries.first;
        for (final candidate in entry.value.entries) {
          if (candidate.value > best.value) best = candidate;
        }
        final uses = entry.value.values.fold(0, (sum, n) => sum + n);
        return (name: entry.key, style: best.key, uses: uses);
      }(),
  ];

  // Most-worn first, then alphabetical, so the list is stable between rebuilds
  // and the house styles are at the top where you look for them.
  styles.sort((a, b) {
    final byUse = b.uses.compareTo(a.uses);
    return byUse != 0
        ? byUse
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return styles;
}

/// [config] wearing [style], with everything that is not a look left alone.
///
/// The whole of "apply". The card keeps its device, its title, its group, its
/// pins, its tap action and every other key it carries — a style writes into
/// one key of the config and reads none of the others.
Map<String, dynamic> applyStyle(Map<String, dynamic> config, CardStyle style) =>
    style.toConfig(config);

/// A name not already taken, as `Style 1`, `Style 2`, …
///
/// Numbered from one and skipping what exists, the same rule `groups.dart`
/// follows: naming, unnaming and naming again gives `Style 1` back rather than
/// climbing forever.
String freshStyleName(Iterable<String> taken, {String stem = 'Style'}) {
  final used = taken.map((n) => n.toLowerCase()).toSet();
  for (var n = 1;; n++) {
    final name = '$stem $n';
    if (!used.contains(name.toLowerCase())) return name;
  }
}
