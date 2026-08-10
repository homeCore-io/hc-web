import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/card_members.dart';

/// A selection is a rule you can disagree with.
///
/// The complaint this answers, in John's words: *"the 'kind' and 'room' on the
/// left panel… should be a shortcut for selecting devices in the room or of
/// those kinds, not a what it is"* and *"I want to be able to choose the
/// devices and remove/add to the groups."*
///
/// The rule stays a **live query** — that is the good part of a room card and
/// the reason it is not simply frozen into a list on the way in: a new lamp in
/// the living room should appear without editing the page. What was missing is
/// the ability to disagree with it about one device, and any way to see what it
/// held at all.

class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _d(String id, String area, {String type = 'light'}) => DeviceState(
      id: id,
      pluginId: 'plugin.test',
      name: id,
      area: area,
      deviceType: type,
      available: true,
      state: const {'on': false},
    );

final _house = [
  _d('lamp', 'living_room'),
  _d('sconce', 'living_room'),
  _d('tv', 'living_room', type: 'media_player'),
  _d('hall_lamp', 'hallway'),
];

void main() {
  group('resolving', () {
    test('the rule alone, when there are no exceptions', () {
      final s = selectDevicesWithCount(
          _house, const {'selection_mode': 'area', 'area_name': 'living_room'});
      expect(s.shown.map((d) => d.id), ['lamp', 'sconce', 'tv']);
    });

    test('the living room except the TV — the sentence that could not be said',
        () {
      final s = selectDevicesWithCount(_house, const {
        'selection_mode': 'area',
        'area_name': 'living_room',
        'remove': ['tv'],
      });
      expect(s.shown.map((d) => d.id), ['lamp', 'sconce']);
    });

    test('and also a device the rule does not reach', () {
      final s = selectDevicesWithCount(_house, const {
        'selection_mode': 'area',
        'area_name': 'living_room',
        'add': ['hall_lamp'],
      });
      expect(s.shown.map((d) => d.id), containsAll(['lamp', 'hall_lamp']));
    });

    test('remove wins over add, so remove means remove', () {
      final s = selectDevicesWithCount(_house, const {
        'selection_mode': 'area',
        'area_name': 'living_room',
        'add': ['hall_lamp'],
        'remove': ['hall_lamp', 'tv'],
      });
      expect(s.shown.map((d) => d.id), ['lamp', 'sconce']);
    });

    test('adding something already matched changes nothing', () {
      final s = selectDevicesWithCount(_house, const {
        'selection_mode': 'area',
        'area_name': 'living_room',
        'add': ['lamp'],
      });
      expect(s.shown.map((d) => d.id), ['lamp', 'sconce', 'tv'],
          reason: 'no duplicate row for a device that was already in');
    });

    test('an id that no longer resolves is ignored, not an error', () {
      // Core deliberately does not check that these exist — a device someone
      // deleted must not make a dashboard unsaveable, or unrenderable.
      final s = selectDevicesWithCount(_house, const {
        'selection_mode': 'area',
        'area_name': 'living_room',
        'add': ['deleted_last_year'],
        'remove': ['also_gone'],
      });
      expect(s.shown.map((d) => d.id), ['lamp', 'sconce', 'tv']);
    });

    test('the rule keeps working — this is not a frozen list', () {
      // The whole reason a room card stores a rule rather than the ids it
      // matched on the day you dragged it.
      final withNewLamp = [..._house, _d('new_lamp', 'living_room')];
      final s = selectDevicesWithCount(withNewLamp, const {
        'selection_mode': 'area',
        'area_name': 'living_room',
        'remove': ['tv'],
      });
      expect(s.shown.map((d) => d.id), contains('new_lamp'),
          reason: 'a new device in the room still appears, and the exception '
              'you made about the TV still holds');
    });
  });

  group('the panel', () {
    late Map<String, dynamic> config;

    Future<void> pump(WidgetTester tester, Map<String, dynamic> initial) async {
      registerBuiltinDashboardWidgets();
      config = initial;
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [devicesProvider.overrideWith(() => _StubDevices(_house))],
        child: MaterialApp(
          theme: hcTheme(HcSkin.midnight, reduceMotion: true),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: CardMembers(
                  config: config,
                  onChanged: (c) => setState(() => config = c),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows what the card holds, and says what the rule was',
        (tester) async {
      await pump(tester, {
        'selection_mode': 'area',
        'area_name': 'living_room',
      });
      expect(find.text('lamp'), findsOneWidget);
      expect(find.text('tv'), findsOneWidget);
      expect(find.text('hall_lamp'), findsNothing,
          reason: 'the rest of the house is behind the search, not in front '
              'of it');
      expect(find.textContaining('Everything in Living Room'), findsOneWidget,
          reason: 'the rule stays visible rather than dissolving into the '
              'list it produced');
    });

    testWidgets('ticking one off writes an exception, not a frozen list',
        (tester) async {
      await pump(tester, {
        'selection_mode': 'area',
        'area_name': 'living_room',
      });
      await tester.tap(find.text('tv'));
      await tester.pumpAndSettle();

      expect(config['remove'], ['tv']);
      expect(config['area_name'], 'living_room',
          reason: 'the rule is untouched — that is the point');
      expect(config.containsKey('device_ids'), isFalse);
    });

    testWidgets('ticking it back on leaves the config as it started',
        (tester) async {
      await pump(tester, {
        'selection_mode': 'area',
        'area_name': 'living_room',
      });
      await tester.tap(find.text('tv'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tv'));
      await tester.pumpAndSettle();

      expect(config.containsKey('remove'), isFalse,
          reason: 'an empty exception list is no exception — a document must '
              'not record every idle tick');
      expect(config.containsKey('add'), isFalse,
          reason: 'and cancelling an exclusion must not invent an inclusion');
    });

    testWidgets('a manual card edits its own list instead', (tester) async {
      // In manual mode the rule already *is* a list, so an exception against
      // your own list would be a second way to say the same thing — and an
      // older client would not read it.
      await pump(tester, {
        'selection_mode': 'manual',
        'device_ids': ['lamp', 'sconce'],
      });
      await tester.tap(find.text('sconce'));
      await tester.pumpAndSettle();

      expect(config['device_ids'], ['lamp']);
      expect(config.containsKey('remove'), isFalse);
    });

    testWidgets('marks why a device is in or out when the rule does not say',
        (tester) async {
      await pump(tester, {
        'selection_mode': 'area',
        'area_name': 'living_room',
        'add': ['hall_lamp'],
      });
      expect(find.text('added'), findsOneWidget);
    });
  });
}
