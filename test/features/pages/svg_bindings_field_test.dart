import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/svg_bindings.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/pages/svg_bindings_field.dart';

/// The binding editor, driven the way a person drives it.
///
/// This exists because the question "does typing four numbers in a row leave
/// four numbers in the document?" was chased through a browser three times and
/// never answered. It is a question about whether a value reaches a map, and a
/// widget test answers it in a second, deterministically, forever.

class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _d(String id) => DeviceState(
      id: id,
      pluginId: 'plugin.test',
      name: id,
      area: 'living_room',
      deviceType: 'sensor',
      available: true,
      state: const {'battery': 80, 'temperature': 21.5},
    );

const _drawing = '<svg><circle id="dial"/><text id="readout">--</text></svg>';

/// A binding that is finished, so the row renders as a real one.
Map<String, dynamic> _wired({String device = 'lamp'}) => {
      svgSourceKey: _drawing,
      'bindings': [
        {
          'id': 'dial',
          'attr': 'stroke-dashoffset',
          'device': device,
          'key': 'battery',
        }
      ],
    };

void main() {
  late Map<String, dynamic> config;

  Future<void> pump(WidgetTester tester, Map<String, dynamic> initial) async {
    config = initial;
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        devicesProvider.overrideWith(() => _StubDevices([_d('lamp')])),
      ],
      child: MaterialApp(
        theme: hcTheme(HcSkin.midnight, reduceMotion: true),
        home: Scaffold(
          body: StatefulBuilder(
            // The feedback loop the real inspector provides. Without it the
            // editor is writing into a void, which is the failure mode the
            // second test below pins.
            builder: (context, setState) => SingleChildScrollView(
              child: SvgBindingsField(
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

  /// Opens the one row, which starts collapsed when its binding is finished.
  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.textContaining('#dial'));
    await tester.pumpAndSettle();
  }

  List<Map<String, dynamic>> bindingsOf(Map<String, dynamic> c) => [
        for (final b in (c['bindings'] as List? ?? const []))
          Map<String, dynamic>.from(b as Map),
      ];

  group('typing a range', () {
    testWidgets('four numbers in a row leave four numbers in the document',
        (tester) async {
      await pump(tester, _wired());
      await expand(tester);

      // The four are the only free-text fields on an expanded numeric row:
      // part, attribute and reading are dropdowns and the device is a button.
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(4));

      await tester.enterText(fields.at(0), '10');
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(1), '90');
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(2), '217');
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(3), '40');
      await tester.pumpAndSettle();

      final binding = bindingsOf(config).single;
      expect(binding['from'], 10);
      expect(binding['to'], 90, reason: 'the second edit must survive');
      expect(binding['out_from'], 217);
      expect(binding['out_to'], 40);
    });

    testWidgets('and the panel then says what the mapping is', (tester) async {
      await pump(tester, _wired());
      await expand(tester);

      final fields = find.byType(TextFormField);
      for (final (i, value) in ['0', '100', '217', '0'].indexed) {
        await tester.enterText(fields.at(i), value);
        await tester.pumpAndSettle();
      }

      // The hint is the only thing on screen that reports whether the range
      // took, so a person who typed four numbers can tell that it did.
      expect(find.textContaining('The reading runs 0–100'), findsOneWidget);
    });

    testWidgets('emptying a field takes the value back out', (tester) async {
      await pump(tester, _wired());
      await expand(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '10');
      await tester.pumpAndSettle();
      expect(bindingsOf(config).single['from'], 10);

      await tester.enterText(fields.at(0), '');
      await tester.pumpAndSettle();
      expect(bindingsOf(config).single.containsKey('from'), isFalse,
          reason: 'a cleared field is not a zero');
    });
  });

  group('the grant', () {
    testWidgets('widens to cover a device a binding names', (tester) async {
      // No `device_ids` at all to begin with: wiring a part to a device and
      // then finding the drawing inert because the element was never given it
      // is a trap with no upside.
      await pump(tester, _wired());
      await expand(tester);

      await tester.enterText(find.byType(TextFormField).at(0), '5');
      await tester.pumpAndSettle();

      expect(config['selection_mode'], 'manual');
      expect(config['device_ids'], contains('lamp'));
    });

    testWidgets('but leaves a rule alone', (tester) async {
      // A grant expressed as a room is a rule the author wrote; converting it
      // to a list of ids would throw that rule away.
      await pump(tester, {
        ..._wired(),
        'selection_mode': 'area',
        'area_name': 'living_room',
      });
      await expand(tester);

      await tester.enterText(find.byType(TextFormField).at(0), '5');
      await tester.pumpAndSettle();

      expect(config['selection_mode'], 'area');
      expect(config.containsKey('device_ids'), isFalse);
    });
  });

  group('the row', () {
    testWidgets('a new one is pre-filled from the drawing and opens itself',
        (tester) async {
      await pump(tester, const {svgSourceKey: _drawing});
      expect(find.textContaining('2 named parts'), findsOneWidget);

      await tester.tap(find.text('Wire up a part'));
      await tester.pumpAndSettle();

      final binding = bindingsOf(config).single;
      expect(binding['id'], 'dial', reason: 'the first unused id in the file');
      // Unfinished, so it opens for you to finish it.
      expect(find.byType(TextFormField), findsNWidgets(4));
    });

    testWidgets('a second one takes the next unused part', (tester) async {
      await pump(tester, _wired());
      await tester.tap(find.text('Wire up a part'));
      await tester.pumpAndSettle();

      expect(bindingsOf(config).map((b) => b['id']), ['dial', 'readout']);
    });

    testWidgets('removing one leaves the others', (tester) async {
      await pump(tester, _wired());
      await tester.tap(find.text('Wire up a part'));
      await tester.pumpAndSettle();
      expect(bindingsOf(config), hasLength(2));

      await tester.tap(find.byTooltip('Remove this binding').first);
      await tester.pumpAndSettle();

      expect(bindingsOf(config).single['id'], 'readout');
    });
  });
}
