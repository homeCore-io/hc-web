import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/floor_plan_card.dart';

/// A picture of the house, with the house on it.
///
/// The claims worth pinning are the ones the design rests on. **The plan is
/// ground and the live state is figure** — so the picture is held back and the
/// markers are the saturated things on it. **A marker is what the device
/// already is** — a sensor draws as its reading, not as a thermometer, because
/// the value is the entire reason it is on the plan. And **a marker is a
/// selection**, so one of them can speak for a room.

class _FakeImages extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? _) => _Client();
}

final _png = Uint8List.fromList(<int>[
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, //
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, //
  0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1, //
  13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

class _Client implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request();
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Request implements HttpClientRequest {
  @override
  final HttpHeaders headers = _Headers();
  @override
  Future<HttpClientResponse> close() async => _Response();
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Response implements HttpClientResponse {
  @override
  int statusCode = HttpStatus.ok;
  @override
  int get contentLength => _png.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  final HttpHeaders headers = _Headers();
  @override
  StreamSubscription<List<int>> listen(void Function(List<int> e)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(_png).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Headers implements HttpHeaders {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

DeviceState _light(String id, {required bool on, String? area}) => DeviceState(
      id: id,
      name: id,
      pluginId: 'plugin.test',
      deviceType: 'light',
      state: {'state': on ? 'on' : 'off', 'on': on},
      available: true,
      areaOverride: area,
    );

DeviceState _sensor(String id, double temp) => DeviceState(
      id: id,
      name: id,
      pluginId: 'plugin.test',
      deviceType: 'temperature_sensor',
      state: {'temperature': temp},
      available: true,
    );

Future<void> _pump(
  WidgetTester tester,
  Map<String, dynamic> config,
  List<DeviceState> devices,
) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [devicesProvider.overrideWith(() => _Devices(devices))],
    child: MaterialApp(
      theme: hcThemeFromTokens(HcSkin.midnight.tokens),
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: FloorPlanCard(config: config),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  setUpAll(() => HttpOverrides.global = _FakeImages());
  tearDownAll(() => HttpOverrides.global = null);

  testWidgets('with no picture it says what to do, not nothing',
      (tester) async {
    await _pump(tester, const {}, const []);
    expect(find.textContaining('floor plan'), findsOneWidget);
  });

  testWidgets('a sensor marker is its reading, not an icon', (tester) async {
    // The value is the entire reason the sensor is on the plan; a thermometer
    // glyph tells you nothing you did not already know.
    await _pump(tester, {
      'url': 'https://house.lan/plan.png',
      'markers': [
        {
          'x': 0.5,
          'y': 0.5,
          'selection': {
            'selection_mode': 'manual',
            'device_ids': ['sensor.hall']
          }
        }
      ],
    }, [
      _sensor('sensor.hall', 21.5)
    ]);
    expect(find.textContaining('21.5'), findsOneWidget);
  });

  testWidgets('one marker can speak for a room', (tester) async {
    // §7.4, and the reason a marker binds to a selection rather than an id:
    // this is room zones without any polygon geometry.
    await _pump(tester, {
      'url': 'https://house.lan/plan.png',
      'markers': [
        {
          'x': 0.5,
          'y': 0.5,
          'label': 'Living Room',
          'selection': {
            'selection_mode': 'area',
            'area_name': 'Living Room',
          }
        }
      ],
    }, [
      _light('light.a', on: false, area: 'Living Room'),
      _light('light.b', on: true, area: 'Living Room'),
      _light('light.elsewhere', on: false, area: 'Kitchen'),
    ]);
    expect(find.text('Living Room'), findsOneWidget);
    // Any of them being on lights the marker — that is what "speaks for the
    // room" means, and it is why `any` and not `every`.
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, isNot(HcSkin.midnight.tokens.surface.onBaseMuted));
  });

  testWidgets('no label by default, so a plan is not a word search',
      (tester) async {
    await _pump(tester, {
      'url': 'https://house.lan/plan.png',
      'markers': [
        {
          'x': 0.2,
          'y': 0.2,
          'selection': {
            'selection_mode': 'manual',
            'device_ids': ['light.a']
          }
        }
      ],
    }, [
      _light('light.a', on: true)
    ]);
    expect(find.text('light.a'), findsNothing,
        reason: 'a marker shows the device name only when asked to');
  });

  testWidgets('a marker that matches nothing says so where it sits',
      (tester) async {
    await _pump(tester, {
      'url': 'https://house.lan/plan.png',
      'markers': [
        {
          'x': 0.5,
          'y': 0.5,
          'selection': {
            'selection_mode': 'manual',
            'device_ids': ['light.deleted']
          }
        }
      ],
    }, const []);
    // Not a blank spot on the plan: something is drawn, in the muted tint.
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, HcSkin.midnight.tokens.surface.onBaseMuted);
  });

  testWidgets('markers are placed by fraction, so they survive a resize',
      (tester) async {
    await _pump(tester, {
      'url': 'https://house.lan/plan.png',
      'markers': [
        {
          'x': 0.25,
          'y': 0.5,
          'selection': {
            'selection_mode': 'manual',
            'device_ids': ['light.a']
          }
        }
      ],
    }, [
      _light('light.a', on: true)
    ]);
    // 0.25 of the 400px box, centred on the point.
    final pos = tester.getCenter(find.byType(Icon));
    expect(pos.dx, closeTo(100, 20));
  });
}

class _Devices extends DevicesNotifier {
  _Devices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}
