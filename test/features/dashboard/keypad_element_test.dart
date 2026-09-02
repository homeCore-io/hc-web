import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/keypad_element.dart';

/// A keypad is not a fact about a room; it is a set of buttons.
///
/// John, on seeing one listed with a dash beside it: *"Lutron keypad the
/// hallway 6 button absolutely can be pressed on the main repeater and should
/// be a controlled device."* These are the claims that makes true.
class _Stub extends DevicesNotifier {
  _Stub(this.items);
  final List<DeviceState> items;
  final sent = <(String, Map<String, dynamic>)>[];
  @override
  Future<List<DeviceState>> build() async => items;
  @override
  Future<void> command(String id, Map<String, dynamic> patch) async =>
      sent.add((id, patch));
}

DeviceState _pad(Map<String, dynamic> state, {bool available = true}) =>
    DeviceState(
      id: 'pad',
      pluginId: 'lutron',
      name: 'Hallway 6 Button',
      deviceType: 'keypad',
      available: available,
      state: state,
    );

Future<_Stub> _pump(
  WidgetTester tester, {
  required DeviceState device,
  Map<String, dynamic> config = const {'device_id': 'pad'},
}) async {
  final stub = _Stub([device]);
  await tester.binding.setSurfaceSize(const Size(600, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [devicesProvider.overrideWith(() => stub)],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(body: Center(child: KeypadElement(config: config))),
    ),
  ));
  await tester.pumpAndSettle();
  return stub;
}

void main() {
  testWidgets('it draws the buttons the device publishes, by name',
      (tester) async {
    await _pump(
      tester,
      device: _pad(const {
        'available_buttons': [
          {'name': 'OH1 Toggle', 'number': 1},
          {'name': 'Outside', 'number': 3},
        ]
      }),
    );
    expect(find.text('OH1 Toggle'), findsOneWidget);
    expect(find.text('Outside'), findsOneWidget);
  });

  testWidgets('a bare number still gets a label', (tester) async {
    // A Pico sends `[2,3,4,5,6]`. "Button 3" is a thing you can look for on a
    // wall; an unlabelled square is not.
    await _pump(
      tester,
      device: _pad(const {
        'available_buttons': [2, 3]
      }),
    );
    expect(find.text('Button 2'), findsOneWidget);
    expect(find.text('Button 3'), findsOneWidget);
  });

  testWidgets('pressing one sends press_button with its number',
      (tester) async {
    final stub = await _pump(
      tester,
      device: _pad(const {
        'available_buttons': [
          {'name': 'Lights', 'number': 3}
        ]
      }),
    );
    await tester.tap(find.text('Lights'));
    await tester.pumpAndSettle();
    expect(stub.sent.single.$1, 'pad');
    expect(stub.sent.single.$2, {'press_button': 3});
  });

  testWidgets('the LED is the state, and it is drawn', (tester) async {
    // A Lutron keypad's LED is the only state it has — it says the scene the
    // button triggers is on. Buttons without it would be a remote control that
    // cannot tell you anything.
    await _pump(
      tester,
      device: _pad(const {
        'available_buttons': [
          {'name': 'Lit', 'number': 1},
          {'name': 'Dark', 'number': 2},
        ],
        'led_1': 'on',
      }),
    );
    final handle = tester.ensureSemantics();
    expect(
      tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((s) => s.properties.toggled == true),
      isNotEmpty,
    );
    handle.dispose();
  });

  testWidgets('a device that publishes no buttons says so', (tester) async {
    // Not an empty box: the author pointed this at the wrong device.
    await _pump(tester, device: _pad(const {}));
    expect(find.textContaining('publishes no buttons'), findsOneWidget);
  });

  testWidgets('an unavailable keypad cannot be pressed, and says so',
      (tester) async {
    final stub = await _pump(
      tester,
      device: _pad(
        const {
          'available_buttons': [
            {'name': 'Lights', 'number': 3}
          ]
        },
        available: false,
      ),
    );
    await tester.tap(find.text('Lights'));
    await tester.pumpAndSettle();
    expect(stub.sent, isEmpty);
    expect(
      tester.widgetList<Opacity>(find.byType(Opacity)).map((o) => o.opacity),
      contains(closeTo(.4, .001)),
    );
  });

  test('buttonsOf reads both spellings and neither breaks the other', () {
    final mixed = buttonsOf(_pad(const {
      'available_buttons': [
        2,
        {'name': 'Deck', 'number': 4},
        {'no': 'number here'},
      ],
      'led_4': true,
      'button_2': 'release',
    }));
    expect(mixed.map((b) => b.number), [2, 4]);
    expect(mixed.first.label, 'Button 2');
    expect(mixed.first.was, 'release');
    expect(mixed.last.label, 'Deck');
    expect(mixed.last.lit, isTrue);
  });

  test('a device with nothing to say gives no buttons', () {
    expect(buttonsOf(null), isEmpty);
    expect(buttonsOf(_pad(const {'available_buttons': 'nonsense'})), isEmpty);
  });
}
