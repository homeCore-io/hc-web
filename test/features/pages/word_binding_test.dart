import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/binding.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/card_inspector.dart';

/// Saying **on** when a light is on.
///
/// A binding that maps values has always been in the document, and the panel
/// only ever offered it for *colour* — so "amber when it is on" was two taps
/// and "say `on` when it is on" could not be said at all. It is the caption
/// under every lamp in the Every Room mockup, and John's rule about that:
/// *"capabilities to build that page need to be expressed in tooling of the UI
/// designer so people can create the same pages as well."* A page that needs a
/// script to write it is a page this editor cannot make.

class _StubDevices extends DevicesNotifier {
  @override
  Future<List<DeviceState>> build() async => [
        DeviceState(
          id: 'lamp',
          pluginId: 'test',
          name: 'Desk lamp',
          available: true,
          state: const {'on': true, 'brightness': 60},
        ),
      ];
}

DashboardWidgetModel textCard(Map<String, dynamic> config) =>
    DashboardWidgetModel(
      id: 'words',
      type: 'text',
      title: 'Words',
      refreshPolicy: DashboardRefreshPolicy.live,
      config: {'text': 'Hello', ...config},
    );

/// The last config the inspector wrote — read *after* the interaction.
///
/// A snapshot returned from the pump is the config before anything happened,
/// which is empty, and asserting about it passes for the wrong reason.
class Wrote {
  Map<String, dynamic> config = const {};

  PropertyBinding? get textBinding =>
      Bindings.fromConfig(config).forProperty('text');
}

Future<Wrote> pumpInspector(
  WidgetTester tester,
  Map<String, dynamic> config,
) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(520, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final wrote = Wrote();
  await tester.pumpWidget(ProviderScope(
    overrides: [devicesProvider.overrideWith(_StubDevices.new)],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: SingleChildScrollView(
          child: CardInspector(
            model: textCard(config),
            onChanged: (c) => wrote.config = c,
            onRemove: () {},
            onClose: () {},
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return wrote;
}

/// The field wearing [label]. `find.ancestor` walks the wrong way for a
/// `TextField`'s own label, which is drawn inside it.
Finder _field(WidgetTester tester, String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(TextField),
    );

void main() {
  testWidgets('a text binding offers words, not a colour swatch',
      (tester) async {
    await pumpInspector(tester, const {
      'bindings': [
        {'property': 'text', 'device_id': 'lamp', 'key': 'on'}
      ],
    });

    expect(find.text('When on'), findsOneWidget);
    expect(find.text('When off'), findsOneWidget);
  });

  testWidgets('typing a word writes it into the map', (tester) async {
    final wrote = await pumpInspector(tester, const {
      'bindings': [
        {'property': 'text', 'device_id': 'lamp', 'key': 'on'}
      ],
    });

    await tester.enterText(_field(tester, 'When on'), 'on');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final binding = wrote.textBinding;
    expect(binding, isNotNull);
    expect(binding!.map['true'], 'on');
    expect(binding.isLookup, isTrue);
  });

  testWidgets('clearing a word removes it rather than printing nothing',
      (tester) async {
    // A map holding one half of a pair would print `false` for the other,
    // which is the raw reading and the thing the map exists to hide.
    final wrote = await pumpInspector(tester, const {
      'bindings': [
        {
          'property': 'text',
          'device_id': 'lamp',
          'key': 'on',
          'map': {'true': 'on', 'false': 'off'},
        }
      ],
    });

    await tester.enterText(_field(tester, 'When off'), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final binding = wrote.textBinding!;
    expect(binding.map.containsKey('false'), isFalse);
    expect(binding.map['true'], 'on');
  });

  group('what the map means, once written', () {
    DeviceState lamp({required bool on}) => DeviceState(
          id: 'lamp',
          pluginId: 'test',
          name: 'Desk lamp',
          available: true,
          state: {'on': on},
        );

    test('a mapped reading shows the word', () {
      const b = PropertyBinding(
        property: 'text',
        deviceId: 'lamp',
        key: 'on',
        map: {'true': 'on', 'false': 'off'},
      );
      expect(b.isLookup, isTrue);
      expect(b.resolve((_) => lamp(on: true)), 'on');
      expect(b.resolve((_) => lamp(on: false)), 'off');
    });

    test('and an unmapped one falls through rather than vanishing', () {
      const b = PropertyBinding(
        property: 'text',
        deviceId: 'lamp',
        key: 'on',
        map: {'true': 'on'},
        fallback: '—',
      );
      expect(b.resolve((_) => lamp(on: false)), '—');
    });
  });
}
