import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/presentation.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/design/skins.dart';

import 'package:hc_web/features/home/home_entity_row.dart';

DeviceState _lock({bool? locked, bool available = true}) => DeviceState(
      id: 'yolink_lock',
      name: 'Garage Exterior Lock',
      pluginId: 'plugin.yolink',
      deviceType: 'lock',
      available: available,
      state: locked == null ? const {} : {'locked': locked},
    );

Future<void> _pump(WidgetTester tester, DeviceState d) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: hcTheme(HcSkin.midnight),
        home: Scaffold(
          body: SizedBox(width: 420, child: HomeEntityRow(device: d)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('a lock is not a switch', () {
    testWidgets('an unlocked lock says so, in words', (tester) async {
      await _pump(tester, _lock(locked: false));
      expect(find.text('UNLOCKED'), findsOneWidget);
      // And offers the safe direction, named.
      expect(find.text('Lock'), findsOneWidget);
    });

    testWidgets('a locked lock says so, in words', (tester) async {
      await _pump(tester, _lock(locked: true));
      expect(find.text('LOCKED'), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);
    });

    /// The bug this locks: a lock reporting no `locked` at all — jammed,
    /// mid-cycle, never polled — used to render as a confident "unlocked",
    /// because a missing bool is not `true`.
    testWidgets('a lock with no reading admits it', (tester) async {
      await _pump(tester, _lock());
      expect(find.text('UNKNOWN'), findsOneWidget);
      expect(find.text('UNLOCKED'), findsNothing);
    });

    testWidgets('an offline lock reads offline, not unlocked', (tester) async {
      await _pump(tester, _lock(locked: false, available: false));
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('UNLOCKED'), findsNothing);
    });
  });

  group('the facet still resolves', () {
    test('a device carrying `locked` is a lock', () {
      expect(facetOf(_lock(locked: true), null), DeviceFacet.lock);
    });

    /// Not a preference — `isOn` feeds the house's "N things on" counts and the
    /// active-first sort, and an unlocked door genuinely is the state worth
    /// surfacing. What changed is only that the *row* stops painting it in the
    /// same amber as a lamp.
    test('an unlocked lock still counts as active', () {
      expect(isOn(_lock(locked: false)), isTrue);
      expect(isOn(_lock(locked: true)), isFalse);
    });
  });
}
