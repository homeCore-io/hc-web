import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/binding.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/card_inspector.dart';

/// Wiring a reading to a property, from the panel.
///
/// The panel builds itself from the descriptor's `bindable` list, so these are
/// about what it *writes* — the document is the contract, and a control that
/// looked right and stored the wrong shape would be the worst outcome.
class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

final _house = [
  DeviceState(
    id: 'lamp',
    pluginId: 'p',
    name: 'Hall lamp',
    deviceType: 'light',
    available: true,
    state: const {'on': true, 'brightness': 62},
  ),
  DeviceState(
    id: 'hob',
    pluginId: 'p',
    name: 'Hob',
    available: true,
    state: const {'temperature': 21.4},
  ),
];

Future<Map<String, dynamic>> _pump(
  WidgetTester tester, {
  String type = 'icon',
  Map<String, dynamic> config = const {'device_id': 'lamp'},
  List<DeviceState>? devices,
}) async {
  registerBuiltinDashboardWidgets();
  final live = <String, dynamic>{...config};
  await tester.binding.setSurfaceSize(const Size(420, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      devicesProvider.overrideWith(() => _StubDevices(devices ?? _house)),
    ],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => CardInspector(
              model: DashboardWidgetModel(
                id: 'a',
                type: type,
                title: 'Hall lamp',
                refreshPolicy: DashboardRefreshPolicy.live,
                config: live,
              ),
              onChanged: (c) => setState(() => live
                ..clear()
                ..addAll(c)),
              onRemove: () {},
              onClose: () {},
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return live;
}

void main() {
  testWidgets('every bindable property is offered, wired or not',
      (tester) async {
    // A list showing only what is already wired would leave the whole feature
    // invisible to anyone who had not been told it exists.
    await _pump(tester);
    // Renamed: "follows the house" named a feeling rather than a thing,
    // and could not say how it differed from the Device field above it.
    expect(find.text('DRIVEN BY A READING'), findsOneWidget);
    expect(find.text('Colour'), findsWidgets);
    expect(find.text('follow a device…'), findsOneWidget);

    // A shape offers four, including two that map through a range.
    await _pump(tester, type: 'shape', config: const {'shape': 'rectangle'});
    expect(find.text('Fill'), findsWidgets);
    expect(find.text('Turn'), findsWidgets);
    // Fill, Fades to, Stroke, Turn, Fade. The count is here to catch a
    // property that quietly stops being offered, not to pin the number — a
    // shape that grows a look worth binding should grow a row here too.
    expect(find.text('follow a device…'),
        findsNWidgets(WidgetRegistry.lookup('shape')!.bindable.length));
  });

  testWidgets('a card that has not thought about it offers nothing',
      (tester) async {
    registerBuiltinDashboardWidgets();
    expect(WidgetRegistry.lookup('markdown')!.bindable, isEmpty);
    expect(WidgetRegistry.lookup('icon')!.bindable, hasLength(1));
    // A shape's whole look is bindable: both ends of its fill, its stroke,
    // its angle and its fade.
    expect(
      {for (final b in WidgetRegistry.lookup('shape')!.bindable) b.name},
      {'fill', 'fill_to', 'stroke', 'rotation', 'opacity'},
    );
    // Every bindable name is a real config key — that rule is what lets a
    // binding resolve INTO the config the element already reads.
    for (final type in ['icon', 'shape', 'text']) {
      final d = WidgetRegistry.lookup(type)!;
      final keys = {for (final f in d.configFields) f.name};
      for (final b in d.bindable) {
        expect(keys, contains(b.name),
            reason: ' binds , which is not one of its fields');
      }
    }
  });

  testWidgets('wiring a colour writes an on/off pair that does something',
      (tester) async {
    final config = await _pump(tester);

    await tester.tap(find.text('follow a device…').first);
    await tester.pumpAndSettle();

    final b = Bindings.fromConfig(config).forProperty('ink')!;
    expect(b.deviceId, 'lamp');
    expect(b.isLookup, isTrue);
    // A binding that changed nothing would look like the row had not worked.
    expect(b.map['true'], isNot(b.map['false']));
  });

  testWidgets('a number property gets a range, not a colour table',
      (tester) async {
    // A shape's Turn — the icon has no number property, because turning an
    // element already belongs to its placement.
    final config = await _pump(tester,
        type: 'shape', config: const {'shape': 'rectangle'});

    // The first number property, wherever the looks happen to sit around it.
    // Counting rows by hand meant that adding a colour to the shape moved this
    // tap onto a different property and failed a test about ranges.
    final turn = WidgetRegistry.lookup('shape')!
        .bindable
        .indexWhere((b) => b.name == 'rotation');
    await tester.tap(find.text('follow a device…').at(turn));
    await tester.pumpAndSettle();

    final b = Bindings.fromConfig(config).forProperty('rotation')!;
    expect(b.isLookup, isFalse);
    expect(find.textContaining('All four, or none'), findsOneWidget);
  });

  testWidgets('changing the device clears the reading it belonged to',
      (tester) async {
    // Keeping it would name a reading the new device does not send — a wire
    // that answers null forever with nothing on screen saying why.
    final config = await _pump(tester);
    await tester.tap(find.text('follow a device…').first);
    await tester.pumpAndSettle();
    expect(Bindings.fromConfig(config).forProperty('ink')!.key, 'brightness');

    // Through the searchable sheet now, the same one every other device
    // field uses — a menu of a hundred and eighty-nine is a menu nobody can
    // find anything in.
    await tester.tap(find.byKey(const ValueKey('bind-device-ink')));
    await tester.pumpAndSettle();
    expect(find.text('Pick devices'), findsOneWidget);
    await tester.tap(find.text('Hob').last);
    await tester.pumpAndSettle();

    final b = Bindings.fromConfig(config).forProperty('ink')!;
    expect(b.deviceId, 'hob');
    expect(b.key, 'temperature');
  });

  testWidgets('unwiring leaves the document as it found it', (tester) async {
    final config = await _pump(tester);
    await tester.tap(find.text('follow a device…').first);
    await tester.pumpAndSettle();
    expect(config.containsKey('bindings'), isTrue);

    final unbind = find.byKey(const ValueKey('unbind-ink'));
    expect(unbind, findsOneWidget);
    await tester.ensureVisible(unbind);
    await tester.pumpAndSettle();
    await tester.tap(unbind);
    await tester.pumpAndSettle();
    expect(config.containsKey('bindings'), isFalse,
        reason: 'an element nobody wired must not keep an empty key');
  });

  testWidgets('a house with nothing in it says so rather than offering a wire',
      (tester) async {
    await _pump(tester, devices: const []);
    expect(find.textContaining('nothing to follow'), findsWidgets);
    expect(find.textContaining('No devices here yet'), findsOneWidget);
  });
}
