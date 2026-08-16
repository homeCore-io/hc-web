import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/clipboard.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/dashboard/groups.dart';
import 'package:hc_web/core/models/dashboard.dart';

/// Taking elements off one page and putting them on another.
///
/// The two failure modes worth guarding are opposites. A paste that is too
/// trusting puts a half-understood card on the page with its settings silently
/// gone — which looks like your work and is not. A paste that is too clever
/// keeps identities or absolute positions, and lands a card on top of itself or
/// somewhere nobody pointed.

DashboardWidgetModel _w(String id, {String? group, String title = 'T'}) =>
    DashboardWidgetModel(
      id: id,
      type: 'markdown',
      title: title,
      refreshPolicy: DashboardRefreshPolicy.passive,
      config: {'markdown': '# $id', if (group != null) 'group': group},
    );

/// Two cards side by side at (2,3) and (6,3), and one far away.
const _items = [
  GridItem(id: 'a', x: 2, y: 3, w: 3, h: 2),
  GridItem(id: 'b', x: 6, y: 3, w: 3, h: 2),
  GridItem(id: 'far', x: 0, y: 9, w: 2, h: 2),
];

final _widgets = {
  'a': _w('a'),
  'b': _w('b'),
  'far': _w('far'),
};

String _stamp(int i) => 'new_$i';

ClipboardCards _roundTrip({
  Iterable<String> ids = const ['a', 'b'],
  Map<String, String?> paths = const {},
  bool composed = false,
  List<GridItem> items = _items,
  Map<String, DashboardWidgetModel>? widgets,
}) {
  final text = encodeCards(
    ids: ids,
    widgets: widgets ?? _widgets,
    items: items,
    paths: paths,
    composed: composed,
  );
  return decodeCards(text)!;
}

void main() {
  group('what goes on the clipboard', () {
    test('nothing selected puts nothing on it', () {
      expect(
        encodeCards(ids: const [], widgets: _widgets, items: _items),
        isNull,
      );
    });

    test('geometry is relative to the cluster, not to the page', () {
      // The property that makes a paste position-independent. Absolute cells
      // would land the copy wherever the original happened to be, which is
      // only ever right by accident.
      final cards = _roundTrip().cards;
      expect(cards.map((c) => (c.dx, c.dy)), [(0, 0), (4, 0)]);
    });

    test('a card that is not selected is not copied', () {
      final cards = _roundTrip().cards;
      expect(cards.map((c) => c.widget.id), ['a', 'b']);
    });

    test('the payload is readable JSON, not an opaque blob', () {
      // A format a person can open is a format they can fix — and the reason
      // this uses the system clipboard rather than an in-memory one.
      final text =
          encodeCards(ids: const ['a'], widgets: _widgets, items: _items)!;
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      expect(decoded['kind'], clipboardKind);
      expect(decoded['version'], clipboardVersion);
      expect((decoded['cards'] as List).single, isA<Map>());
    });
  });

  group('what comes off it', () {
    test('somebody else’s clipboard is not ours', () {
      // Paste has to do *nothing* here, not paste an empty page. Without the
      // kind check every stray string would decode as a valid empty payload.
      expect(decodeCards('hello'), isNull);
      expect(decodeCards('{"kind":"something.else","cards":[]}'), isNull);
      expect(decodeCards(''), isNull);
      expect(decodeCards(null), isNull);
    });

    test('a version this build cannot read is refused, not guessed', () {
      final text =
          encodeCards(ids: const ['a'], widgets: _widgets, items: _items)!;
      final bumped = jsonDecode(text) as Map<String, dynamic>;
      bumped['version'] = clipboardVersion + 1;
      expect(decodeCards(jsonEncode(bumped)), isNull,
          reason: 'guessing would paste a card with settings quietly dropped');
    });

    test('a damaged card is dropped, and the rest still paste', () {
      final text =
          encodeCards(ids: const ['a', 'b'], widgets: _widgets, items: _items)!;
      final payload = jsonDecode(text) as Map<String, dynamic>;
      (payload['cards'] as List)[0] = {'widget': 'not a map'};
      final out = decodeCards(jsonEncode(payload));
      expect(out!.cards.map((c) => c.widget.id), ['b']);
    });

    test('a payload with no usable card at all is null', () {
      expect(
          decodeCards('{"kind":"$clipboardKind","version":'
              '$clipboardVersion,"cards":[]}'),
          isNull);
    });
  });

  group('landing it on a page', () {
    test('every pasted card gets a new identity', () {
      // A widget id is unique within a page, so pasting back onto the page it
      // came from would collide with itself — and core rejects the whole
      // dashboard, not the one card.
      final out = pasteInto(
          cards: _roundTrip(), columns: 12, atX: 0, atY: 0, stamp: _stamp);
      expect(out.items.map((i) => i.id), ['new_0', 'new_1']);
      expect(out.widgets.keys, ['new_0', 'new_1']);
      expect(out.widgets['new_0']!.id, 'new_0',
          reason: 'the model must carry the new id, not just the map key');
    });

    test('the arrangement survives the trip', () {
      final out = pasteInto(
          cards: _roundTrip(), columns: 12, atX: 1, atY: 5, stamp: _stamp);
      expect(out.items.map((i) => (i.x, i.y)), [(1, 5), (5, 5)]);
    });

    test('it lands where it was asked to, not where it came from', () {
      final out = pasteInto(
          cards: _roundTrip(), columns: 12, atX: 0, atY: 0, stamp: _stamp);
      expect(out.items.first.x, 0);
      expect(out.items.first.y, 0);
    });

    test('a card wider than the target grid is clamped, not dropped', () {
      // Same rule deriving a layout follows: on a four-column phone a wide
      // desktop card becomes as wide as fits, which is what anyone would have
      // drawn anyway.
      final out = pasteInto(
          cards: _roundTrip(), columns: 2, atX: 0, atY: 0, stamp: _stamp);
      expect(out.items.every((i) => i.w <= 2), isTrue);
      expect(out.items.every((i) => i.x + i.w <= 2), isTrue,
          reason: 'core rejects a placement past the column count');
    });
  });

  group('groups', () {
    test('a copied group comes with its members', () {
      final out = pasteInto(
        cards: _roundTrip(paths: const {'a': 'Wall', 'b': 'Wall'}),
        columns: 12,
        atX: 0,
        atY: 0,
        stamp: _stamp,
      );
      final paths = out.widgets.values.map((w) => groupOf(w.config)).toSet();
      expect(paths, {'Wall'});
    });

    test('a name already on the page is renamed, not merged', () {
      // Two groups that happen to share a name are not the same group, and
      // merging them would silently put a stranger's cards in yours.
      final out = pasteInto(
        cards: _roundTrip(paths: const {'a': 'Wall', 'b': 'Wall'}),
        columns: 12,
        atX: 0,
        atY: 0,
        stamp: _stamp,
        taken: {'Wall'},
      );
      final paths = out.widgets.values.map((w) => groupOf(w.config)).toSet();
      expect(paths.length, 1,
          reason: 'both members land in the SAME new group');
      expect(paths.single, isNot('Wall'));
    });

    test('a card that was in no group stays in none', () {
      final out = pasteInto(
          cards: _roundTrip(), columns: 12, atX: 0, atY: 0, stamp: _stamp);
      expect(out.widgets.values.map((w) => groupOf(w.config)),
          everyElement(isNull));
    });
  });

  group('compositions', () {
    const composed = [
      GridItem(
        id: 'a',
        x: 2,
        y: 3,
        w: 3,
        h: 2,
        rect: DashboardRect(x: 240.5, y: 360.0, w: 420.0, h: 260.0),
      ),
      GridItem(
        id: 'b',
        x: 6,
        y: 3,
        w: 3,
        h: 2,
        rect: DashboardRect(x: 700.5, y: 360.0, w: 420.0, h: 260.0),
      ),
    ];

    test('rectangles are relative too, and survive between compositions', () {
      final out = pasteInto(
        cards: _roundTrip(items: composed, composed: true),
        columns: 12,
        atX: 0,
        atY: 0,
        stamp: _stamp,
        composedTarget: true,
      );
      expect(out.items[0].rect!.x, 0);
      expect(out.items[1].rect!.x, 460.0,
          reason: 'the gap between them is preserved exactly');
    });

    test('a composition pasted into a plain grid keeps only its cells', () {
      // A rectangle stated on a 1600-wide canvas means nothing on a page that
      // has none. The cells come through instead — which is the fallback the
      // whole two-representation design exists for.
      final out = pasteInto(
        cards: _roundTrip(items: composed, composed: true),
        columns: 12,
        atX: 0,
        atY: 0,
        stamp: _stamp,
        composedTarget: false,
      );
      expect(out.items.every((i) => i.rect == null), isTrue);
      expect(out.items.map((i) => (i.x, i.w)), [(0, 3), (4, 3)]);
    });

    test('plain cards pasted onto a canvas do not invent rectangles', () {
      final out = pasteInto(
        cards: _roundTrip(),
        columns: 12,
        atX: 0,
        atY: 0,
        stamp: _stamp,
        composedTarget: true,
      );
      expect(out.items.every((i) => i.rect == null), isTrue);
    });
  });

  test('a card keeps everything that made it worth copying', () {
    // The whole point. Re-adding from the library and reconfiguring is exactly
    // what this exists to avoid, so the config has to arrive intact.
    const tuned = DashboardWidgetModel(
      id: 'g',
      type: 'gauge',
      title: 'Boiler',
      subtitle: 'flow',
      refreshPolicy: DashboardRefreshPolicy.passive,
      config: {
        'device_id': 'boiler_1',
        'min': 20,
        'max': 90,
        'sweep': 270,
        'bands': [
          {'from': 20, 'to': 60, 'colour': 'ok'}
        ],
      },
    );
    final out = pasteInto(
      cards: _roundTrip(
        ids: const ['g'],
        widgets: {'g': tuned},
        items: const [GridItem(id: 'g', x: 0, y: 0, w: 3, h: 3)],
      ),
      columns: 12,
      atX: 0,
      atY: 0,
      stamp: _stamp,
    );
    final pasted = out.widgets.values.single;
    expect(pasted.type, 'gauge');
    expect(pasted.title, 'Boiler');
    expect(pasted.subtitle, 'flow');
    expect(pasted.config['bands'], tuned.config['bands']);
    expect(pasted.config['sweep'], 270);
  });
}
