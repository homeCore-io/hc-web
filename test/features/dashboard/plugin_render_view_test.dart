import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/plugin_render.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/plugin_render_view.dart';

class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

DeviceState _boiler(Map<String, dynamic> state) => DeviceState(
      id: 'boiler_1',
      pluginId: 'boiler',
      name: 'Boiler',
      available: true,
      state: state,
    );

PluginWidgetSpec _spec(Object render, {List<Object> bindings = const []}) =>
    PluginWidgetSpec.fromJson({
      'plugin_id': 'boiler',
      'widget_id': 'boiler_flow',
      'title': 'Boiler flow',
      'bindings': bindings,
      'render': render,
    })!;

Future<void> _pump(
  WidgetTester tester,
  PluginWidgetSpec spec, {
  Map<String, dynamic> config = const {'device_id': 'boiler_1'},
  List<DeviceState> devices = const [],
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [devicesProvider.overrideWith(() => _StubDevices(devices))],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 300,
          child: PluginRenderView(spec: spec, config: config),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a literal text element draws its words', (tester) async {
    await _pump(
      tester,
      _spec({'kind': 'text', 'content': 'Boiler'}),
      devices: [_boiler(const {})],
    );
    expect(find.text('Boiler'), findsOneWidget);
  });

  testWidgets('text bound to a reading draws the reading, with its unit',
      (tester) async {
    // `content` naming a binding is what makes a portable card show live data
    // at all — without it a declaration could only draw fixed words.
    await _pump(
      tester,
      _spec(
        {'kind': 'text', 'content': 'flow', 'unit': 'L/min', 'decimals': 1},
        bindings: [
          {
            'name': 'flow',
            'device': '{{config.device_id}}',
            'key': 'flow_lpm',
          }
        ],
      ),
      devices: [
        _boiler(const {'flow_lpm': 12.25})
      ],
    );
    expect(find.text('12.3 L/min'), findsOneWidget);
  });

  testWidgets('a reading that is not there is a dash, never a zero',
      (tester) async {
    // A gauge at zero is a claim about the house. "We do not know" is not it,
    // and the two must never look the same.
    await _pump(
      tester,
      _spec(
        {'kind': 'text', 'content': 'flow', 'unit': 'L/min'},
        bindings: [
          {
            'name': 'flow',
            'device': '{{config.device_id}}',
            'key': 'flow_lpm',
          }
        ],
      ),
      devices: [_boiler(const {})],
    );
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('a container draws its children in order', (tester) async {
    await _pump(
      tester,
      _spec({
        'kind': 'column',
        'gap': 8,
        'children': [
          {'kind': 'text', 'content': 'Flow'},
          {'kind': 'text', 'content': 'Return'},
        ],
      }),
      devices: [_boiler(const {})],
    );
    expect(find.text('Flow'), findsOneWidget);
    expect(find.text('Return'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Flow')).dy,
      lessThan(tester.getTopLeft(find.text('Return')).dy),
    );
  });

  testWidgets('an element this build does not know says so', (tester) async {
    // Core validated the kind against the element vocabulary, so the card is
    // not wrong — this app is behind, and an empty rectangle would blame the
    // wrong thing.
    await _pump(
      tester,
      _spec({'kind': 'sparkline'}),
      devices: [_boiler(const {})],
    );
    expect(find.textContaining('Needs a newer app'), findsOneWidget);
  });

  testWidgets('a card nobody finished configuring reads nothing at all',
      (tester) async {
    // The template does not resolve, so the binding names no device. It must
    // not fall back to reading a device literally called `{{config.device_id}}`
    // and reporting the house is missing one.
    await _pump(
      tester,
      _spec(
        {'kind': 'text', 'content': 'flow'},
        bindings: [
          {
            'name': 'flow',
            'device': '{{config.device_id}}',
            'key': 'flow_lpm',
          }
        ],
      ),
      config: const {},
      devices: [
        _boiler(const {'flow_lpm': 12.0})
      ],
    );
    expect(find.text('—'), findsOneWidget);
  });
}
