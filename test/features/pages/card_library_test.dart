import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/api/assets_api.dart';
import 'package:hc_web/core/providers/assets_provider.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/card_library.dart';

/// The library is a view of the house, and that is the whole point.
///
/// The palette it replaces listed thirteen card types and was byte-identical on
/// a homeCore with no devices — it could not have told you your house has a
/// living room. These tests fail if it ever goes back to being a static list.

class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _d(String id, String area, {bool on = false, String? type}) =>
    DeviceState(
      id: id,
      pluginId: 'plugin.test',
      name: id,
      area: area,
      deviceType: type ?? 'light',
      available: true,
      state: {'on': on},
    );

/// Tall enough to hold the whole catalogue at once.
///
/// It grew when the elements that were registered-but-unreachable joined the
/// list — the switch, the slider, the icon, the stepper, the colour wheel, the
/// warmth bar, the scene button, and the three cards that had been in no picker
/// at all. These tests are about what the catalogue *contains*, so the surface
/// holds it rather than every assertion learning to scroll.
const double _tall = 2600;
Future<List<DashboardWidgetModel>> _pump(
  WidgetTester tester,
  List<DeviceState> devices, {
  List<AssetRef>? assets,
}) async {
  registerBuiltinDashboardWidgets();
  final picked = <DashboardWidgetModel>[];
  await tester.binding.setSurfaceSize(const Size(420, _tall));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      devicesProvider.overrideWith(() => _StubDevices(devices)),
      assetListProvider.overrideWith((ref) async => assets ?? const []),
    ],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(body: CardLibrary(onPick: picked.add)),
    ),
  ));
  await tester.pumpAndSettle();
  return picked;
}

void main() {
  final house = [
    _d('a', 'living_room', on: true),
    _d('b', 'living_room'),
    _d('c', 'living_room', on: true),
    _d('d', 'office'),
    _d('scene1', 'living_room', type: 'scene'),
  ];

  group('it shows this house', () {
    testWidgets('rooms, with how many and how many are on', (tester) async {
      // Both numbers survive the move from a row to a tile: the total is on
      // the tile's face, and the live count is on the tooltip. A room is a
      // real thing rather than a label because of the two of them.
      await _pump(tester, house);
      expect(find.text('Living Room'), findsOneWidget);
      expect(find.text('Office'), findsOneWidget);
      expect(find.byTooltip('Living Room — 3 devices, 2 on'), findsOneWidget,
          reason: 'two of the living room devices are on');
    });

    testWidgets('scenes are not devices in a room', (tester) async {
      // A plugin's scenes arrive as devices with an area. Counting them would
      // inflate every room by however many scenes the bridge exposes.
      await _pump(tester, house);
      expect(find.text('3'), findsOneWidget,
          reason: 'living room has 3 real devices, not 4');
    });

    testWidgets('a house with no rooms says what to do about it',
        (tester) async {
      await _pump(tester, [_d('x', '')]);
      expect(find.textContaining('No rooms yet'), findsOneWidget);
    });

    testWidgets('it says nothing about rooms before the house has loaded',
        (tester) async {
      // Claiming "no rooms yet" while devices are still arriving is the same
      // lie as a card claiming "no devices match" mid-load.
      registerBuiltinDashboardWidgets();
      await tester.binding.setSurfaceSize(const Size(420, _tall));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: hcTheme(HcSkin.midnight, reduceMotion: true),
          home: Scaffold(body: CardLibrary(onPick: (_) {})),
        ),
      ));
      await tester.pump();
      expect(find.textContaining('No rooms yet'), findsNothing);
    });
  });

  group('placing', () {
    testWidgets('a room becomes a card for that room, already configured',
        (tester) async {
      final picked = await _pump(tester, house);
      await tester.tap(find.text('Living Room'));
      await tester.pumpAndSettle();

      expect(picked, hasLength(1));
      final card = picked.single;
      expect(card.config['selection_mode'], 'area');
      expect(card.config['area_name'], 'living_room',
          reason: 'the stored value, not the label it was shown under');
      expect(card.title, 'Living Room',
          reason: 'a card called "Device grid" would be naming its renderer '
              'at the person who asked for a room');
    });

    testWidgets('a house card comes with sensible defaults', (tester) async {
      final picked = await _pump(tester, house);
      await tester.tap(find.text('THE HOUSE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(picked.single.type, 'event_feed');
      expect(picked.single.config['limit'], 20);
    });
  });

  group('search', () {
    testWidgets('narrows rooms and cards together', (tester) async {
      await _pump(tester, house);
      await tester.enterText(find.byType(TextField), 'off');
      await tester.pumpAndSettle();

      // Twice: the room, and the device in it. Searching now reaches both —
      // a room is the answer most of the time, but "the office lamp" is a
      // thing people look for, and it had no way in at all before.
      expect(find.text('Office'), findsNWidgets(2));
      expect(find.text('Living Room'), findsNothing);
    });
  });

  group('pictures', () {
    // They had no way into a page at all: uploading worked, four config fields
    // could pick one, and placing a picture still meant making an image element
    // and then finding the address to type into it.

    testWidgets('the ones this house has, as things you can place',
        (tester) async {
      await _pump(tester, house, assets: [
        const AssetRef(
            id: 'a1', contentType: 'image/png', size: 10, name: 'hallway.png'),
        const AssetRef(
            id: 'a2', contentType: 'image/jpeg', size: 20, name: 'porch.jpg'),
      ]);
      expect(find.text('PICTURES'), findsOneWidget);
      expect(find.byTooltip('hallway.png'), findsOneWidget);
      expect(find.byTooltip('porch.jpg'), findsOneWidget);
    });

    testWidgets('clicking one places an image already pointing at it',
        (tester) async {
      final picked = await _pump(tester, house, assets: [
        const AssetRef(
            id: 'a1', contentType: 'image/png', size: 10, name: 'hallway.png'),
      ]);
      await tester.tap(find.byTooltip('hallway.png'));
      await tester.pumpAndSettle();
      expect(picked.single.type, 'image');
      expect(picked.single.config['url'], contains('a1'));
      // Named for the file, so the layer tree says which picture rather than
      // "Image" four times.
      expect(picked.single.title, 'hallway.png');
    });

    testWidgets('only pictures — a font is not something you place',
        (tester) async {
      await _pump(tester, house, assets: [
        const AssetRef(
            id: 'f1', contentType: 'font/ttf', size: 10, name: 'Inter.ttf'),
      ]);
      expect(find.byTooltip('Inter.ttf'), findsNothing);
    });

    testWidgets('an empty store says how to fill it', (tester) async {
      await _pump(tester, house, assets: const []);
      expect(find.textContaining('Nothing uploaded yet'), findsOneWidget);
    });

    testWidgets('says it is looking, rather than claiming there is nothing',
        (tester) async {
      // "Nothing uploaded yet" is a claim about the house and it is false
      // while the question is in flight — but rendering *nothing* instead made
      // the section appear not to exist, which is how it went missing on the
      // live house with no way to tell why. The header stays; only the claim
      // waits.
      registerBuiltinDashboardWidgets();
      await tester.binding.setSurfaceSize(const Size(420, _tall));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          devicesProvider.overrideWith(() => _StubDevices(house)),
          assetListProvider
              .overrideWith((ref) => Completer<List<AssetRef>>().future),
        ],
        child: MaterialApp(
          theme: hcTheme(HcSkin.midnight, reduceMotion: true),
          home: Scaffold(body: CardLibrary(onPick: (_) {})),
        ),
      ));
      await tester.pump();
      expect(find.textContaining('Nothing uploaded yet'), findsNothing);
      expect(find.text('PICTURES'), findsOneWidget);
      expect(find.text('Looking…'), findsOneWidget);
    });

    testWidgets('a listing that fails says so, rather than vanishing',
        (tester) async {
      registerBuiltinDashboardWidgets();
      await tester.binding.setSurfaceSize(const Size(420, _tall));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          devicesProvider.overrideWith(() => _StubDevices(house)),
          assetListProvider
              .overrideWith((ref) async => throw Exception('no route')),
        ],
        child: MaterialApp(
          theme: hcTheme(HcSkin.midnight, reduceMotion: true),
          home: Scaffold(body: CardLibrary(onPick: (_) {})),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not list your files'), findsOneWidget);
    });
  });

  group('groups', () {
    testWidgets('nothing is hidden behind a caret', (tester) async {
      // The accordion was the honest answer while every entry was a full-width
      // row: fifteen rooms pushed everything else into the bottom third of the
      // panel, so anything that was not a room read as an afterthought. Tiles
      // are three to a row, so the whole catalogue fits — and a palette whose
      // contents are behind carets is a browser rather than a palette.
      await _pump(tester, house);
      expect(find.text('Living Room'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Gauge'), findsOneWidget);
    });

    testWidgets('a section still says how much is in it', (tester) async {
      await _pump(tester, house);
      expect(find.text('THE HOUSE'), findsOneWidget);
      expect(find.text('6'), findsWidgets,
          reason: 'the count is what tells you a section is complete');
    });

    testWidgets('search still narrows to a hit', (tester) async {
      await _pump(tester, house);
      await tester.enterText(find.byType(TextField), 'activ');
      await tester.pumpAndSettle();
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Gauge'), findsNothing);
    });
  });

  group('individual devices', () {
    testWidgets('are hidden until you search', (tester) async {
      // A hundred and twenty rows above the rooms would bury them, and the
      // room is the answer most of the time.
      await _pump(tester, house);
      expect(find.text('a'), findsNothing);
    });

    testWidgets('gets no container, because it is not a collection',
        (tester) async {
      // "Placing several single devices next to each other would consume lots
      // of unnecessary space" — a 3×1 cell is 100px, and a title band plus two
      // lots of padding took most of it. The tile already carries the device's
      // own name and state, so the band said it twice.
      final picked = await _pump(tester, house);
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pumpAndSettle();
      await tester.tap(find.text('a').last);
      await tester.pumpAndSettle();

      expect(picked.single.config['style'],
          {'filled': false, 'bordered': false, 'titled': false});
    });

    testWidgets('a searched device places a tile for that one device',
        (tester) async {
      final picked = await _pump(tester, house);
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pumpAndSettle();
      await tester.tap(find.text('a').last);
      await tester.pumpAndSettle();

      expect(picked.single.type, 'device_tile');
      expect(picked.single.config['selection_mode'], 'manual');
      expect(picked.single.config['device_ids'], ['a'],
          reason: 'the device you searched for, already chosen — "manual mode" '
              'is what this was always for, without making anyone meet the '
              'word');
    });
  });

  group('kinds', () {
    // Withheld until core learned `selection_mode: facet`, and the reason is
    // worth keeping now that they are here. `/devices` offers "Lights 22",
    // computed from each device's facet; the nearest stored selection was
    // `query: "light"`, which matches on the NAME and found 17 of those 22. A
    // chip labelled 22 that places a card showing 17 is the silent wrongness
    // this whole arc has been removing, so the honest answer was to offer
    // nothing until the count could be kept.

    testWidgets('are the kinds this house actually has', (tester) async {
      await _pump(tester, house);
      // Four lights in a house of four lights and one scene.
      expect(find.text('Lights'), findsOneWidget);
      // And nothing for the kinds nobody owns — a chip saying "Sirens 0"
      // offers a card that is guaranteed to be empty.
      expect(find.text('Sirens'), findsNothing);
      expect(find.text('Locks'), findsNothing);
    });

    testWidgets('count what the card will show, past the same exclusions',
        (tester) async {
      // The scene is excluded here exactly as it is from the room counts and
      // from the card itself, so the number beside the name is the number you
      // get. Four devices; the scene is not one of them.
      await _pump(tester, house);
      final tile = find.ancestor(
          of: find.text('Lights'), matching: find.byType(Tooltip));
      expect(find.descendant(of: tile.first, matching: find.text('4')),
          findsWidgets,
          reason: 'four lights, not five — the scene is not a light');
    });

    testWidgets('placing one stores a facet selection, not a query',
        (tester) async {
      final picked = await _pump(tester, house);
      await tester.tap(find.text('Lights'));
      await tester.pumpAndSettle();

      expect(picked, hasLength(1));
      expect(picked.single.config['selection_mode'], 'facet');
      expect(picked.single.config['facet'], 'lights');
      expect(picked.single.config['query'], isNull,
          reason: 'a query for the word is the thing this replaces');
      expect(picked.single.title, 'Lights',
          reason: 'named for what was picked, as a room card is');
    });

    testWidgets('and the card it places really does select them',
        (tester) async {
      // The claim the whole mode exists for: the chip says four and the card
      // shows four. Resolved through the same function the card renders from.
      final picked = await _pump(tester, house);
      await tester.tap(find.text('Lights'));
      await tester.pumpAndSettle();

      final selection = selectDevicesWithCount(house, picked.single.config);
      expect(selection.matched, 4);
    });
  });
}
