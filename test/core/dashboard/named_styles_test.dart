import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/card_style.dart';
import 'package:hc_web/core/dashboard/named_styles.dart';
import 'package:hc_web/core/models/dashboard.dart';

/// Saved looks, and the two things that must stay true about them.
///
/// **Applying is a copy.** A card that took a style is an ordinary card
/// afterwards, and editing it reaches nothing else — which is why there is no
/// registry here to keep in step and no live link to reason about.
///
/// **A style is a look and nothing else.** It has no device, no title, no
/// position and no size, so no amount of applying can move a card's wiring. The
/// tests at the bottom are the ones worth reading: they say what a style cannot
/// do, which is the part that has to hold.

DashboardWidgetModel card(
  String id, {
  String? style,
  String? tint,
  String? deviceId,
  bool bordered = false,
}) =>
    DashboardWidgetModel(
      id: id,
      type: 'toggle',
      title: id,
      refreshPolicy: DashboardRefreshPolicy.live,
      config: CardStyle(
        name: style,
        filled: true,
        bordered: bordered,
        titled: false,
        tint: tint,
      ).toConfig({if (deviceId != null) 'device_id': deviceId}),
    );

DashboardDefinition page(String id, List<DashboardWidgetModel> widgets) =>
    DashboardDefinition(
      id: id,
      name: id,
      description: null,
      ownerUserId: 'u1',
      visibility: DashboardVisibility.private,
      tags: const [],
      icon: 'grid',
      isDefault: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      layouts: const [],
      widgets: widgets,
    );

void main() {
  group('the library is derived, not stored', () {
    test('a style exists as long as a card wears it', () {
      final library = namedStylesIn([
        page('a', [card('one', style: 'Panel'), card('two', style: 'Panel')]),
      ]);
      expect(library, hasLength(1));
      expect(library.single.name, 'Panel');
      expect(library.single.uses, 2);
    });

    test('and stops existing when the last one is renamed', () {
      // No orphan, nothing to clean up — the argument `groups.dart` makes
      // about paths, for the same reason.
      expect(
          namedStylesIn([
            page('a', [card('one')])
          ]),
          isEmpty);
    });

    test('it spans every page you can see', () {
      final library = namedStylesIn([
        page('office', [card('one', style: 'Panel')]),
        page('kitchen',
            [card('two', style: 'Panel'), card('three', style: 'Rail')]),
      ]);
      expect([for (final s in library) s.name], ['Panel', 'Rail']);
      expect(library.first.uses, 2);
    });

    test('most-worn first, then alphabetical', () {
      final library = namedStylesIn([
        page('a', [
          card('1', style: 'Zebra'),
          card('2', style: 'Zebra'),
          card('3', style: 'Alpha'),
          card('4', style: 'Beta'),
        ]),
      ]);
      expect([for (final s in library) s.name], ['Zebra', 'Alpha', 'Beta']);
    });

    test('an unnamed style is not in the library', () {
      final library = namedStylesIn([
        page('a', [card('one', tint: 'accent')]),
      ]);
      expect(library, isEmpty);
    });

    test('a name of nothing but spaces is no name', () {
      const widget = DashboardWidgetModel(
        id: 'one',
        type: 'toggle',
        title: 'One',
        refreshPolicy: DashboardRefreshPolicy.live,
        config: {
          'style': {'name': '   ', 'filled': false}
        },
      );
      expect(
          namedStylesIn([
            page('a', [widget])
          ]),
          isEmpty);
    });
  });

  group('two cards wearing one name may disagree', () {
    test('because editing after applying is the whole point', () {
      // Not a conflict to resolve. One of them was customised, which is what
      // "applied and then able to be customized" means.
      final library = namedStylesIn([
        page('a', [
          card('1', style: 'Panel', tint: 'raised'),
          card('2', style: 'Panel', tint: 'raised'),
          card('3', style: 'Panel', tint: 'danger'),
        ]),
      ]);
      expect(library, hasLength(1));
      expect(library.single.uses, 3);
      expect(library.single.style.tint, 'raised',
          reason: 'the commonest spelling wins; the odd one out is a change '
              'somebody made and must not redefine what it came from');
    });
  });

  group('applying', () {
    test('writes the look and the name', () {
      final saved = const CardStyle(
        name: 'Panel',
        filled: true,
        bordered: false,
        titled: false,
        tint: 'raised',
        corner: 'lg',
      );
      final out = CardStyle.fromConfig(applyStyle(const {}, saved));
      expect(out.name, 'Panel');
      expect(out.tint, 'raised');
      expect(out.corner, 'lg');
      expect(out.bordered, isFalse);
    });

    test('leaves the card wired exactly as it was', () {
      // **The assertion this whole file exists for.** A style has no device
      // field, so applying one cannot move a card's wiring — not to a
      // different light, not on this page, not on any other.
      const wired = {
        'device_id': 'hue_0x1234',
        'group': 'Panel',
        'pin': {'x': 'end', 'y': 'start'},
        'on_tap': {'kind': 'scene', 'scene_id': 'evening'},
      };
      final out = applyStyle(
          wired, const CardStyle(name: 'Panel', filled: true, titled: false));

      expect(out['device_id'], 'hue_0x1234');
      expect(out['group'], 'Panel');
      expect(out['pin'], {'x': 'end', 'y': 'start'});
      expect(out['on_tap'], {'kind': 'scene', 'scene_id': 'evening'});
    });

    test('and changes nothing on any other card', () {
      // There is no mechanism by which it could — this is the absence of a
      // feature, asserted so that adding one is a deliberate act.
      final one = card('one', style: 'Panel', tint: 'raised');
      final two = card('two', style: 'Panel', tint: 'raised');
      final edited = one.copyWith(
        config: applyStyle(one.config,
            CardStyle.fromConfig(one.config).copyWith(tint: 'danger')),
      );

      expect(CardStyle.fromConfig(edited.config).tint, 'danger');
      expect(CardStyle.fromConfig(two.config).tint, 'raised');
    });
  });

  group('naming', () {
    test('a name alone does not write a style into the document', () {
      // A card whose look is the default look wears the default look. Naming
      // it must not be able to put nine properties into a page that says
      // nothing today.
      expect(const CardStyle().called('Panel').toConfig(const {}), const {});
    });

    test('a name survives the round trip', () {
      const style = CardStyle(name: 'Panel', filled: false, titled: false);
      expect(CardStyle.fromConfig(style.toConfig(const {})).name, 'Panel');
    });

    test('unnaming takes the name back out and leaves the look', () {
      const style = CardStyle(name: 'Panel', filled: false, titled: false);
      final plain = style.called(null);
      expect(plain.name, isNull);
      expect(plain.filled, isFalse);
      expect(plain.toConfig(const {})['style'], isNot(contains('name')));
    });

    test('a fresh name skips what is taken, and comes back to one', () {
      expect(freshStyleName(const []), 'Style 1');
      expect(freshStyleName(const ['Style 1', 'Style 2']), 'Style 3');
      expect(freshStyleName(const ['style 1']), 'Style 2',
          reason: 'case is not a difference anybody means');
      expect(freshStyleName(const ['Style 2']), 'Style 1');
    });
  });
}
