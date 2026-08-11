import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/dashboard.dart';
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
  List<DeviceState> devices, {
  bool entered = false,
  ValueChanged<Map<String, dynamic>>? onConfigChanged,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [devicesProvider.overrideWith(() => _Devices(devices))],
    child: MaterialApp(
      theme: hcThemeFromTokens(HcSkin.midnight.tokens),
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: FloorPlanCard(
            config: config,
            entered: entered,
            onConfigChanged: onConfigChanged,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// The card wired to a document that actually takes the writes.
///
/// [_pump] hands the card a config it can never change, which is right for
/// asking *what did it write*. It is useless for the inspector, where the point
/// is the round trip: a label typed into the card has to come back as the
/// card's own config or the field is editing a ghost.
class _Live extends StatefulWidget {
  const _Live({required this.initial, required this.seen});
  final Map<String, dynamic> initial;
  final List<Map<String, dynamic>> seen;

  @override
  State<_Live> createState() => _LiveState();
}

class _LiveState extends State<_Live> {
  late Map<String, dynamic> _config = widget.initial;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 400,
        height: 300,
        child: FloorPlanCard(
          config: _config,
          entered: true,
          onConfigChanged: (next) {
            widget.seen.add(next);
            setState(() => _config = next);
          },
        ),
      );
}

/// Returns every config the card wrote, in order; the last is the document.
Future<List<Map<String, dynamic>>> _pumpLive(
  WidgetTester tester,
  Map<String, dynamic> config,
  List<DeviceState> devices,
) async {
  final seen = <Map<String, dynamic>>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [devicesProvider.overrideWith(() => _Devices(devices))],
    child: MaterialApp(
      theme: hcThemeFromTokens(HcSkin.midnight.tokens),
      home: Scaffold(body: _Live(initial: config, seen: seen)),
    ),
  ));
  await tester.pump();
  return seen;
}

List<Map<String, dynamic>> _markersOf(Map<String, dynamic> config) => [
      for (final m in (config['markers'] as List? ?? const []))
        (m as Map).cast<String, dynamic>(),
    ];

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

  _editModeTests();
  _dropTests();
  _inspectorTests();

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

Map<String, dynamic> _oneMarker({double x = 0.5, double y = 0.5}) => {
      'url': 'https://house.lan/plan.png',
      'markers': [
        {
          'x': x,
          'y': y,
          'selection': {
            'selection_mode': 'manual',
            'device_ids': ['light.a']
          }
        }
      ],
    };

// ── placing markers ────────────────────────────────────────────────────────

class _Devices extends DevicesNotifier {
  _Devices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

void _editModeTests() {
  testWidgets('a marker is inert until the card is entered', (tester) async {
    // A viewer must not be one drag from rearranging the house — and in the
    // designer, a card you have not entered is an object you arrange, so the
    // markers on it are part of the picture.
    Map<String, dynamic>? written;
    await _pump(tester, _oneMarker(), [_light('light.a', on: true)],
        onConfigChanged: (c) => written = c);
    await tester.drag(find.byType(Icon).first, const Offset(-100, 0));
    await tester.pump();
    expect(written, isNull);
  });

  testWidgets('nor when nobody is listening for the result', (tester) async {
    // Entered with no writer is the designer drawing a preview. A gesture whose
    // result goes nowhere is worse than one that is refused.
    await _pump(tester, _oneMarker(), [_light('light.a', on: true)],
        entered: true);
    await tester.drag(find.byType(Icon).first, const Offset(-100, 0));
    await tester.pump();
    expect(find.textContaining('Drag a device'), findsNothing,
        reason: 'nothing here can be placed, so nothing invites it');
  });

  testWidgets('dragging a marker writes a fraction, not a pixel',
      (tester) async {
    Map<String, dynamic>? written;
    await _pump(
        tester, _oneMarker(x: 0.5, y: 0.5), [_light('light.a', on: true)],
        entered: true, onConfigChanged: (c) => written = c);

    // The card is 400x300 and the marker sits at its centre. Drag it a
    // quarter of the width left.
    await tester.drag(find.byType(Icon).first, const Offset(-100, 0));
    await tester.pump();

    expect(written, isNotNull, reason: 'the move never reached the document');
    final marker = (written!['markers'] as List).first as Map;
    expect(marker['x'], closeTo(0.25, 0.05));
    expect(marker['y'], closeTo(0.5, 0.05));
    expect(marker['x'], isNot(isA<int>()),
        reason: 'a pixel would be right exactly once, at one card size');
  });

  testWidgets('a drag past the edge parks at it', (tester) async {
    Map<String, dynamic>? written;
    await _pump(
        tester, _oneMarker(x: 0.1, y: 0.5), [_light('light.a', on: true)],
        entered: true, onConfigChanged: (c) => written = c);
    await tester.drag(find.byType(Icon).first, const Offset(-400, 0));
    await tester.pump();

    final marker = (written!['markers'] as List).first as Map;
    expect(marker['x'], 0.0, reason: 'clamped, so it stays findable');
  });

  testWidgets('the rest of the config survives a move', (tester) async {
    // The card rewrites its own document here, and dropping `url` or `dim`
    // on the way would blank the plan the marker sits on.
    Map<String, dynamic>? written;
    final config = {..._oneMarker(), 'dim': 0.7, 'invert': true};
    await _pump(tester, config, [_light('light.a', on: true)],
        entered: true, onConfigChanged: (c) => written = c);
    await tester.drag(find.byType(Icon).first, const Offset(-40, 0));
    await tester.pump();

    expect(written!['url'], 'https://house.lan/plan.png');
    expect(written!['dim'], 0.7);
    expect(written!['invert'], true);
  });
}

void _dropTests() {
  DashboardWidgetModel payload(Map<String, dynamic> config) =>
      DashboardWidgetModel(
        id: 'w',
        type: 'device_tile',
        title: 'Living Room',
        refreshPolicy: DashboardRefreshPolicy.passive,
        config: config,
      );

  test('a dropped card contributes its selection and nothing else', () {
    // The library drags a whole card. What carries over to a marker is which
    // devices it meant; the rest described a card that is not being made.
    final selection = selectionFromPayload(const {
      'selection_mode': 'area',
      'area_name': 'Living Room',
      'show_offline': true,
      'title_visible': false,
      'style': {'image': 'x'},
    });
    expect(selection, {
      'selection_mode': 'area',
      'area_name': 'Living Room',
      'show_offline': true,
    });
    expect(selection.containsKey('style'), isFalse);
  });

  testWidgets('an empty plan, once entered, says what to do', (tester) async {
    await _pump(tester, const {'url': 'https://house.lan/plan.png'}, const [],
        entered: true, onConfigChanged: (_) {});
    expect(find.textContaining('Drag a device'), findsOneWidget);
  });

  testWidgets('dropping a device makes a marker where it landed',
      (tester) async {
    // Driven through the DragTarget's own contract rather than by simulating a
    // pointer: what is being checked is that a drop at a global point becomes
    // the right fraction of the card, and a synthetic drag adds Flutter's
    // machinery to the thing under test without adding coverage.
    Map<String, dynamic>? written;
    await _pump(tester, const {'url': 'https://house.lan/plan.png'},
        [_light('light.a', on: true)],
        entered: true, onConfigChanged: (c) => written = c);

    final target =
        tester.widget<DragTarget<Object>>(find.byType(DragTarget<Object>));
    final topLeft = tester.getTopLeft(find.byType(FloorPlanCard));
    final dropped = payload(const {
      'selection_mode': 'manual',
      'device_ids': ['light.a'],
    });

    expect(
      target.onWillAcceptWithDetails!(
          DragTargetDetails<Object>(data: dropped, offset: topLeft)),
      isTrue,
      reason: 'in place mode the plan claims the drop',
    );
    // A quarter across and half down a 400x300 card.
    target.onAcceptWithDetails!(DragTargetDetails<Object>(
        data: dropped, offset: Offset(topLeft.dx + 100, topLeft.dy + 150)));
    await tester.pump();

    expect(written, isNotNull, reason: 'the drop never reached the document');
    final markers = written!['markers'] as List;
    expect(markers, hasLength(1));
    final m = markers.first as Map;
    expect(m['x'], closeTo(0.25, 0.06));
    expect(m['y'], closeTo(0.5, 0.06));
    expect((m['selection'] as Map)['device_ids'], ['light.a']);
    expect(m.containsKey('label'), isFalse,
        reason: 'a plan that starts life labelled is a word search');
  });

  testWidgets('a drop is ignored until the card is entered', (tester) async {
    // The canvas beneath is itself a drop target — that is how a card gets
    // placed — and two things claiming the same drop would make which one you
    // got depend on pixels.
    Map<String, dynamic>? written;
    await _pump(tester, const {'url': 'https://house.lan/plan.png'}, const [],
        onConfigChanged: (c) => written = c);
    final target =
        tester.widget<DragTarget<Object>>(find.byType(DragTarget<Object>));
    expect(
      target.onWillAcceptWithDetails!(DragTargetDetails<Object>(
          data: payload(const {'selection_mode': 'manual'}),
          offset: Offset.zero)),
      isFalse,
      reason: 'not in place mode, so the plan does not claim the drop',
    );
    expect(written, isNull);
  });
}

// ── the marker inspector ───────────────────────────────────────────────────

/// A marker you can place and never name or delete is what shipped first, and
/// it made a misplaced marker permanent. This is the smallest panel that fixes
/// that: what it speaks for, what to call it, and the way to get rid of it.

Map<String, dynamic> _room(String area, {double x = 0.5, double y = 0.5}) => {
      'x': x,
      'y': y,
      'selection': {'selection_mode': 'area', 'area_name': area},
    };

void _inspectorTests() {
  testWidgets('there is no panel until you touch a marker', (tester) async {
    await _pumpLive(tester, {
      'markers': [_room('living_room')]
    }, [
      _light('light.a', on: true, area: 'living_room')
    ]);
    expect(find.text('Label'), findsNothing,
        reason: 'an inspector nobody asked for is a plan you cannot see');
  });

  testWidgets('touching one says which marker it is about', (tester) async {
    // On a plan with eight markers, a panel that does not name its subject is
    // one you have to verify before daring to press Remove.
    await _pumpLive(tester, {
      'markers': [_room('living_room')]
    }, [
      _light('light.a', on: true, area: 'living_room')
    ]);
    await tester.tap(find.byType(Icon).first);
    await tester.pump();

    expect(find.text('Living Room'), findsOneWidget);
    expect(find.text('Label'), findsOneWidget);
  });

  testWidgets('a marker with a name of your own keeps it in the document',
      (tester) async {
    final seen = await _pumpLive(tester, {
      'markers': [_room('living_room')]
    }, [
      _light('light.a', on: true, area: 'living_room')
    ]);
    await tester.tap(find.byType(Icon).first);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Sofa lamp');
    await tester.pump();

    expect(_markersOf(seen.last).single['label'], 'Sofa lamp',
        reason: 'the custom label is the whole reason labels are per marker');
    // And it is on the plan, not only in the document.
    expect(find.text('Sofa lamp'), findsWidgets);
  });

  testWidgets('clearing the name removes it rather than storing an empty one',
      (tester) async {
    final seen = await _pumpLive(tester, {
      'markers': [
        {..._room('living_room'), 'label': 'Sofa lamp'}
      ]
    }, [
      _light('light.a', on: true, area: 'living_room')
    ]);
    await tester.tap(find.byType(Icon).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();

    expect(_markersOf(seen.last).single.containsKey('label'), isFalse,
        reason: '"no label" is a choice, not an empty string');
  });

  testWidgets('Remove takes the marker off the plan', (tester) async {
    final seen = await _pumpLive(tester, {
      'markers': [_room('living_room'), _room('kitchen', x: 0.8)]
    }, [
      _light('light.a', on: true, area: 'living_room'),
      _light('light.b', on: true, area: 'kitchen'),
    ]);
    await tester.tap(find.byType(Icon).first);
    await tester.pump();
    await tester.tap(find.text('Remove'));
    await tester.pump();

    final markers = _markersOf(seen.last);
    expect(markers, hasLength(1));
    expect((markers.single['selection'] as Map)['area_name'], 'kitchen',
        reason: 'the wrong one was removed');
    expect(find.text('Label'), findsNothing,
        reason: 'the panel outlived the marker it was about');
  });

  testWidgets('and so does Delete, on the marker you just touched',
      (tester) async {
    // The keyboard route matters because removing is the commoner of the two
    // things you come to this panel for: a marker dropped in the wrong room.
    final seen = await _pumpLive(tester, {
      'markers': [_room('living_room')]
    }, [
      _light('light.a', on: true, area: 'living_room')
    ]);
    await tester.tap(find.byType(Icon).first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    expect(_markersOf(seen.last), isEmpty);
  });

  testWidgets('Escape puts the panel away before it leaves the card',
      (tester) async {
    // Two-stage on purpose: one key that always undoes the last thing you got
    // into. The second stage — leaving the card — is the frame's, and is
    // proved in the grid's own tests.
    await _pumpLive(tester, {
      'markers': [_room('living_room')]
    }, [
      _light('light.a', on: true, area: 'living_room')
    ]);
    await tester.tap(find.byType(Icon).first);
    await tester.pump();
    expect(find.text('Label'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Label'), findsNothing);
  });

  testWidgets('clicking the plan puts it away too', (tester) async {
    await _pumpLive(tester, {
      'markers': [_room('living_room')]
    }, [
      _light('light.a', on: true, area: 'living_room')
    ]);
    await tester.tap(find.byType(Icon).first);
    await tester.pump();

    // The top-left corner of the 400x300 card: plan, no marker on it.
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    expect(find.text('Label'), findsNothing);
  });

  testWidgets('dragging a marker selects it, so the panel is about it',
      (tester) async {
    await _pumpLive(tester, {
      'markers': [_room('living_room')]
    }, [
      _light('light.a', on: true, area: 'living_room')
    ]);
    await tester.drag(find.byType(Icon).first, const Offset(-60, 0));
    await tester.pump();

    expect(find.text('Living Room'), findsOneWidget,
        reason: 'the panel is about the marker already under your finger');
  });

  testWidgets('a marker pointing at nothing still says so in the panel',
      (tester) async {
    await _pumpLive(tester, {
      'markers': [
        {
          'x': 0.5,
          'y': 0.5,
          'selection': {
            'selection_mode': 'manual',
            'device_ids': ['light.deleted'],
          },
        }
      ]
    }, const []);
    await tester.tap(find.byType(Icon).first);
    await tester.pump();

    expect(find.text('Nothing here now'), findsOneWidget,
        reason: 'the panel is how you find and remove a marker gone stale');
  });
}
