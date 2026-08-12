import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/floor_plan.dart';
import 'package:hc_web/core/dashboard/sweet_home.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/floor_plan_card.dart';
import 'package:hc_web/features/dashboard/plan_view.dart';
import 'package:hc_web/features/devices/device_sheet.dart';

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

DeviceState _light(String id,
        {required bool on, String? area, int? brightnessPct}) =>
    DeviceState(
      id: id,
      name: id,
      pluginId: 'plugin.test',
      deviceType: 'light',
      state: {
        'state': on ? 'on' : 'off',
        'on': on,
        if (brightnessPct != null) 'brightness_pct': brightnessPct,
      },
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

/// Returns the house the card was talking to, so a test can ask what it heard.
Future<_Devices> _pump(
  WidgetTester tester,
  Map<String, dynamic> config,
  List<DeviceState> devices, {
  bool entered = false,
  HcSkin skin = HcSkin.midnight,
  ValueChanged<Map<String, dynamic>>? onConfigChanged,
}) async {
  final house = _Devices(devices);
  await tester.pumpWidget(ProviderScope(
    overrides: [devicesProvider.overrideWith(() => house)],
    child: MaterialApp(
      theme: hcThemeFromTokens(skin.tokens),
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
  return house;
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
  _pressTests();
  _drawnHomeTests();
  _importedMarkerTests();
  _roomPressTests();
  _bindFromRoomTests();
  _bindOrderTests();

  testWidgets('naming a marker does not move it', (tester) async {
    // It did. The label was a sibling of the dot in a Row and the whole row was
    // centred on the point, so naming a marker slid its dot half the name's
    // width to the left — further the longer the name — while the document went
    // on saying the fraction it was placed at. Right value, wrong drawing, on
    // the plan and in view mode alike.
    Offset dot() => tester.getCenter(find.byType(Icon));

    await _pump(tester, _oneMarker(), [_light('light.a', on: true)]);
    final bare = dot();

    final named = _oneMarker();
    (named['markers'] as List).first['label'] = 'Sofa lamp in the far corner';
    await _pump(tester, named, [_light('light.a', on: true)]);

    expect(dot(), bare,
        reason: 'the name is drawn beside the dot, not around it');
    // And the dot is where the fraction says: the middle of a 400x300 card.
    expect(bare.dx, closeTo(200, 1));
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

  /// Every command the card sent, in order — the only honest record of what a
  /// press actually asked the house to do.
  final sent = <(String, Map<String, dynamic>)>[];

  @override
  Future<List<DeviceState>> build() async => items;

  @override
  Future<void> command(String id, Map<String, dynamic> patch) async =>
      sent.add((id, patch));
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

// ── pressing a marker ──────────────────────────────────────────────────────

/// §7.4, the half that makes a plan a way to work the house rather than a
/// picture of it: a marker glows if any of its devices are on, and pressing it
/// turns *all* of them off. That is room zones without polygon geometry.

/// What the card asked the house to do, flattened — records holding maps do not
/// compare by value, and `{'on': false}` is the whole payload anyway.
List<String> _asked(_Devices house) =>
    [for (final (id, patch) in house.sent) '$id ${patch['on']}'];

/// What a marker is to anyone not looking at the glow.
SemanticsNode _nodeOf(WidgetTester tester, Finder marker) =>
    tester.getSemantics(marker);

void _pressTests() {
  testWidgets('pressing a lit room turns the whole room off', (tester) async {
    final house = await _pump(tester, {
      'markers': [_room('living_room')]
    }, [
      _light('light.a', on: true, area: 'living_room'),
      _light('light.b', on: false, area: 'living_room'),
      _light('light.elsewhere', on: true, area: 'kitchen'),
    ]);

    await tester.tap(find.byType(Icon));
    await tester.pump();

    expect(_asked(house), ['light.a false', 'light.b false'],
        reason: 'all of them, and only the ones the marker speaks for');
  });

  testWidgets('and pressing a dark one turns it on', (tester) async {
    final house = await _pump(tester, {
      'markers': [_room('living_room')]
    }, [
      _light('light.a', on: false, area: 'living_room'),
      _light('light.b', on: false, area: 'living_room'),
    ]);

    await tester.tap(find.byType(Icon));
    await tester.pump();

    expect(_asked(house), ['light.a true', 'light.b true']);
  });

  testWidgets('the marker says what pressing it will do', (tester) async {
    // The glow says "on" to anyone looking at it and nothing at all to anyone
    // who is not, so the same decision that drives the press names the marker.
    final handle = tester.ensureSemantics();
    await _pump(tester, {
      'markers': [_room('living_room')]
    }, [
      _light('light.a', on: true, area: 'living_room')
    ]);

    expect(_nodeOf(tester, find.byType(Icon)).label, 'Living Room, on');
    handle.dispose();
  });

  testWidgets('a custom name is the one the marker answers to', (tester) async {
    final handle = tester.ensureSemantics();
    final marker = _room('living_room');
    marker['label'] = 'Sofa lamp';
    await _pump(tester, {
      'markers': [marker]
    }, [
      _light('light.a', on: false, area: 'living_room')
    ]);

    expect(_nodeOf(tester, find.byType(Icon)).label, 'Sofa lamp, off');
    handle.dispose();
  });

  testWidgets('a sensor is not a switch — it opens its details',
      (tester) async {
    // "On" is the wrong verb for a thermometer, and a marker that ignores the
    // tap is worse than one that shows you the thing you pressed.
    final house = await _pump(tester, {
      'markers': [
        {
          'x': 0.5,
          'y': 0.5,
          'selection': {
            'selection_mode': 'manual',
            'device_ids': ['sensor.hall'],
          },
        }
      ]
    }, [
      _sensor('sensor.hall', 21.5)
    ]);

    await tester.tap(find.textContaining('21.5'));
    await tester.pumpAndSettle();

    expect(house.sent, isEmpty, reason: 'a sensor was told to switch on');
    expect(find.byType(DevicePanel), findsOneWidget);
  });

  testWidgets('a marker pointing at nothing is not pressable', (tester) async {
    final handle = tester.ensureSemantics();
    final house = await _pump(tester, {
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

    await tester.tap(find.byType(Icon));
    await tester.pump();

    expect(house.sent, isEmpty);
    expect(
        _nodeOf(tester, find.byType(Icon))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
        reason: 'a dead affordance is worse than none');
    handle.dispose();
  });

  testWidgets('inside the card a press selects, and works nothing',
      (tester) async {
    // The designer is arranging the plan, not operating the house. Pressing a
    // marker there must never reach a light.
    final house = await _pump(
        tester,
        {
          'markers': [_room('living_room')]
        },
        [_light('light.a', on: true, area: 'living_room')],
        entered: true,
        onConfigChanged: (_) {});

    await tester.tap(find.byType(Icon).first);
    await tester.pump();

    expect(house.sent, isEmpty, reason: 'the designer switched a real light');
    expect(find.text('Label'), findsOneWidget, reason: 'it selected instead');
  });
}

// ── a marker on a drawn home ───────────────────────────────────────────────

/// The card is the wrong frame for an imported home. Its shape changes with the
/// breakpoint and the drawing is letterboxed inside it, so a marker held as a
/// fraction of the *card* slides off the room it was put in the moment the card
/// is a different shape.

const _wide = HomePlan(walls: [
  PlanWall(x1: 0, y1: 0, x2: 1000, y2: 0),
  PlanWall(x1: 0, y1: 200, x2: 1000, y2: 200),
]);

Map<String, dynamic> _drawnHome({PlanPoint? at}) => {
      'plan': _wide.toJson(),
      'markers': [
        FloorPlanMarker(
          selection: const {
            'selection_mode': 'manual',
            'device_ids': ['light.a'],
          },
          // A card fraction that is deliberately *wrong* for the home point, so
          // a test cannot pass by accident on the fallback.
          x: 0.9,
          y: 0.9,
          home: at ?? const PlanPoint(500, 100),
        ).toJson(),
      ],
    };

void _drawnHomeTests() {
  testWidgets('a marker on a home holds its room through a reshape',
      (tester) async {
    Future<Offset> dotIn(Size card) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          devicesProvider
              .overrideWith(() => _Devices([_light('light.a', on: true)])),
        ],
        child: MaterialApp(
          theme: hcThemeFromTokens(HcSkin.midnight.tokens),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: card.width,
                height: card.height,
                child: FloorPlanCard(config: _drawnHome()),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      final card0 = tester.getTopLeft(find.byType(FloorPlanCard));
      return tester.getCenter(find.byType(Icon)) - card0;
    }

    // The same point of the home, drawn into two very differently shaped cards.
    for (final card in [const Size(600, 200), const Size(300, 500)]) {
      final expected = PlanFit.of(_wide, card)!.toCard(500, 100);
      final actual = await dotIn(card);
      expect(actual.dx, closeTo(expected.dx, 1),
          reason: 'the marker left the home at $card');
      expect(actual.dy, closeTo(expected.dy, 1),
          reason: 'the marker left the home at $card');
    }
  });

  testWidgets('dragging one writes centimetres, not a fraction of the card',
      (tester) async {
    Map<String, dynamic>? written;
    await _pump(tester, _drawnHome(), [_light('light.a', on: true)],
        entered: true, onConfigChanged: (c) => written = c);

    await tester.drag(find.byType(Icon).first, const Offset(-40, 0));
    await tester.pump();

    final marker = (written!['markers'] as List).single as Map;
    expect(marker['hx'], isNotNull);
    expect(marker['hy'], isNotNull);
    // The card is 400 wide and the home 1000cm, letterboxed — so 40pt of
    // pointer is more than 40cm of house.
    expect(marker['hx'] as double, lessThan(500));
    expect(marker['hx'] as double, greaterThan(300));
  });

  testWidgets('and a home taken away leaves its markers roughly where they sat',
      (tester) async {
    // Both frames are stored, so removing the geometry falls back to the card
    // fraction rather than piling every marker in one corner.
    final config = _drawnHome()..remove('plan');
    await _pump(tester, config, [_light('light.a', on: true)]);
    final dot = tester.getCenter(find.byType(Icon)) -
        tester.getTopLeft(find.byType(FloorPlanCard));
    expect(dot.dx, closeTo(0.9 * 400, 1));
    expect(dot.dy, closeTo(0.9 * 300, 1));
  });
}

// ── markers the import placed ──────────────────────────────────────────────

/// §7.9: every `<light>` in the file has a position, so an import can do the
/// tedious half — a marker per lamp, already in the right room. It cannot do
/// the other half: `<light name="Ceiling lamp">` will not match a device called
/// `Overhead`, and a guess is a plan that quietly works the wrong lamp.

const _lit = HomePlan(
  rooms: [
    PlanRoom(name: 'Living Room', points: [
      PlanPoint(0, 0),
      PlanPoint(400, 0),
      PlanPoint(400, 400),
      PlanPoint(0, 400),
    ]),
  ],
  furniture: [
    PlanPiece(name: 'Ceiling lamp', x: 200, y: 200, light: true),
    PlanPiece(name: 'Sofa', x: 100, y: 300, width: 100, depth: 50),
  ],
);

void _importedMarkerTests() {
  test('an import places one marker per light, and binds none of them', () {
    final placed = candidateMarkers(_lit);
    expect(placed, hasLength(1), reason: 'the sofa is not a lamp');
    expect(placed.single.home, const PlanPoint(200, 200));
    expect(placed.single.label, 'Ceiling lamp',
        reason: "the file's own name is the only way to tell dots apart");
    expect(isUnbound(placed.single), isTrue);
  });

  testWidgets(
      'an unbound marker matches nothing — it does not glow for the '
      'whole house', (tester) async {
    // The trap this avoids: an *empty* selection falls through to query mode,
    // and a marker matching everything would light whenever any lamp anywhere
    // was on.
    final house = await _pump(
      tester,
      {
        'plan': _lit.toJson(),
        'markers': [for (final m in candidateMarkers(_lit)) m.toJson()],
      },
      [_light('light.a', on: true), _light('light.b', on: true)],
    );

    await tester.tap(find.byType(Icon).first, warnIfMissed: false);
    await tester.pump();
    expect(house.sent, isEmpty, reason: 'an unbound marker worked a light');
  });

  testWidgets('the panel says it is not bound, and how to bind it',
      (tester) async {
    await _pumpLive(
      tester,
      {
        'plan': _lit.toJson(),
        'markers': [for (final m in candidateMarkers(_lit)) m.toJson()],
      },
      const [],
    );
    await tester.tap(find.byType(Icon).first);
    await tester.pump();

    expect(find.text('Not bound yet'), findsOneWidget);
    expect(find.textContaining('Drop a device on it'), findsOneWidget);
  });

  testWidgets('dropping a device on one binds it instead of adding another',
      (tester) async {
    Map<String, dynamic>? written;
    await _pump(
      tester,
      {
        'plan': _lit.toJson(),
        'markers': [for (final m in candidateMarkers(_lit)) m.toJson()],
      },
      [_light('light.a', on: true)],
      entered: true,
      onConfigChanged: (c) => written = c,
    );

    final target =
        tester.widget<DragTarget<Object>>(find.byType(DragTarget<Object>));
    // Straight onto the lamp the import placed.
    final onMarker = tester.getCenter(find.byType(Icon).first);
    target.onAcceptWithDetails!(DragTargetDetails<Object>(
      data: const DashboardWidgetModel(
        id: 'w',
        type: 'device_tile',
        title: 'A light',
        refreshPolicy: DashboardRefreshPolicy.passive,
        config: {
          'selection_mode': 'manual',
          'device_ids': ['light.a'],
        },
      ),
      offset: onMarker,
    ));
    await tester.pump();

    final markers = (written!['markers'] as List).cast<Map>();
    expect(markers, hasLength(1), reason: 'a second dot was laid on the first');
    expect((markers.single['selection'] as Map)['device_ids'], ['light.a']);
    expect(markers.single['label'], 'Ceiling lamp',
        reason: 'the name the file gave it survives being bound');
    expect(markers.single['hx'], 200,
        reason: 'and so does the place the file put it');
  });

  testWidgets('a drop away from any of them still places a new marker',
      (tester) async {
    Map<String, dynamic>? written;
    await _pump(
      tester,
      {
        'plan': _lit.toJson(),
        'markers': [for (final m in candidateMarkers(_lit)) m.toJson()],
      },
      [_light('light.a', on: true)],
      entered: true,
      onConfigChanged: (c) => written = c,
    );

    final target =
        tester.widget<DragTarget<Object>>(find.byType(DragTarget<Object>));
    final corner = tester.getTopLeft(find.byType(FloorPlanCard));
    target.onAcceptWithDetails!(DragTargetDetails<Object>(
      data: const DashboardWidgetModel(
        id: 'w',
        type: 'device_tile',
        title: 'A light',
        refreshPolicy: DashboardRefreshPolicy.passive,
        config: {
          'selection_mode': 'manual',
          'device_ids': ['light.a'],
        },
      ),
      offset: corner + const Offset(12, 12),
    ));
    await tester.pump();

    expect((written!['markers'] as List), hasLength(2));
  });
}

// ── pressing a room ────────────────────────────────────────────────────────

/// §7.4 called zones deferred and offered a marker bound to a room as the
/// honest 80%. For an imported home the polygon is *in the file*, so the 80%
/// becomes the whole thing: press the kitchen, not a dot in the kitchen.

const _twoRooms = HomePlan(rooms: [
  PlanRoom(name: 'Living Room', points: [
    PlanPoint(0, 0),
    PlanPoint(400, 0),
    PlanPoint(400, 400),
    PlanPoint(0, 400),
  ]),
  PlanRoom(name: 'Cellar', points: [
    PlanPoint(400, 0),
    PlanPoint(800, 0),
    PlanPoint(800, 400),
    PlanPoint(400, 400),
  ]),
]);

void _roomPressTests() {
  testWidgets('pressing a room turns that room off', (tester) async {
    final house = await _pump(tester, {
      'plan': _twoRooms.toJson()
    }, [
      _light('light.a', on: true, area: 'living_room'),
      _light('light.b', on: true, area: 'living_room'),
    ]);

    // The middle of the living room half of the card.
    final card = tester.getRect(find.byType(FloorPlanCard));
    await tester.tapAt(Offset(card.left + card.width * 0.25, card.center.dy));
    await tester.pump();

    expect(_asked(house), ['light.a false', 'light.b false']);
  });

  testWidgets('a room the house has no area for is not pressable',
      (tester) async {
    // An exact match after humanising, never anything fuzzy: a room that
    // quietly worked a different room's lights is the worst bug this card
    // could have.
    final house = await _pump(tester, {
      'plan': _twoRooms.toJson()
    }, [
      _light('light.a', on: true, area: 'living_room'),
    ]);

    final card = tester.getRect(find.byType(FloorPlanCard));
    // Over the Cellar, which no device claims.
    await tester.tapAt(Offset(card.left + card.width * 0.75, card.center.dy));
    await tester.pump();

    expect(house.sent, isEmpty);
  });

  testWidgets('a marker standing in a room is still what you press',
      (tester) async {
    // The dot is the specific thing and the room is the general one, so the
    // dot has to win where they overlap.
    final house = await _pump(
      tester,
      {
        'plan': _twoRooms.toJson(),
        'markers': [
          const FloorPlanMarker(
            selection: {
              'selection_mode': 'manual',
              'device_ids': ['light.only'],
            },
            x: 0.5,
            y: 0.5,
            home: PlanPoint(200, 200),
          ).toJson(),
        ],
      },
      [
        _light('light.a', on: true, area: 'living_room'),
        _light('light.only', on: true, area: 'living_room'),
      ],
    );

    await tester.tap(find.byType(Icon).first);
    await tester.pump();

    expect(_asked(house), ['light.only false'],
        reason: 'the room took a press meant for the marker on it');
  });

  testWidgets('rooms are inert inside the card, where the plan is being drawn',
      (tester) async {
    final house = await _pump(
      tester,
      {'plan': _twoRooms.toJson()},
      [_light('light.a', on: true, area: 'living_room')],
      entered: true,
      onConfigChanged: (_) {},
    );

    final card = tester.getRect(find.byType(FloorPlanCard));
    await tester.tapAt(Offset(card.left + card.width * 0.25, card.center.dy));
    await tester.pump();

    expect(house.sent, isEmpty, reason: 'the designer switched a real light');
  });

  testWidgets('a room says its name and its state', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, {'plan': _twoRooms.toJson()},
        [_light('light.a', on: true, area: 'living_room')]);

    expect(find.bySemanticsLabel('Living Room, on'), findsOneWidget);
    handle.dispose();
  });
}

// ── binding from the room ──────────────────────────────────────────────────

/// §7.9's payoff: the file says which room the lamp hangs in, so binding it is
/// a choice among that room's four things rather than a hunt through 188.

void _bindFromRoomTests() {
  Map<String, dynamic> importedLiving() => {
        'plan': const HomePlan(rooms: [
          PlanRoom(name: 'Living Room', points: [
            PlanPoint(0, 0),
            PlanPoint(400, 0),
            PlanPoint(400, 400),
            PlanPoint(0, 400),
          ]),
        ], furniture: [
          PlanPiece(name: 'Ceiling lamp', x: 200, y: 200, light: true),
        ]).toJson(),
        'markers': [
          for (final m in candidateMarkers(const HomePlan(furniture: [
            PlanPiece(name: 'Ceiling lamp', x: 200, y: 200, light: true),
          ])))
            m.toJson(),
        ],
      };

  testWidgets('the panel offers what is in that room', (tester) async {
    await _pumpLive(tester, importedLiving(), [
      _light('light.sofa', on: false, area: 'living_room'),
      _light('light.reading', on: false, area: 'living_room'),
      _light('light.kitchen', on: false, area: 'kitchen'),
    ]);
    await tester.tap(find.byType(Icon).first);
    await tester.pump();

    expect(find.text('In Living Room:'), findsOneWidget);
    expect(find.text('light.sofa'), findsOneWidget);
    expect(find.text('light.reading'), findsOneWidget);
    expect(find.text('light.kitchen'), findsNothing,
        reason: 'the kitchen is not this lamp\'s room');
    expect(find.text('The whole room'), findsOneWidget);
  });

  testWidgets('picking one binds the marker to it', (tester) async {
    final seen = await _pumpLive(tester, importedLiving(), [
      _light('light.sofa', on: false, area: 'living_room'),
    ]);
    await tester.tap(find.byType(Icon).first);
    await tester.pump();
    await tester.tap(find.text('light.sofa'));
    await tester.pump();

    final marker = _markersOf(seen.last).single;
    expect((marker['selection'] as Map)['device_ids'], ['light.sofa']);
    expect(marker['label'], 'Ceiling lamp', reason: 'the name it came with');
    expect(marker['hx'], 200, reason: 'and the place it came with');
  });

  testWidgets('or to the room itself, which is what §7.4 is built around',
      (tester) async {
    final seen = await _pumpLive(tester, importedLiving(), [
      _light('light.sofa', on: false, area: 'living_room'),
    ]);
    await tester.tap(find.byType(Icon).first);
    await tester.pump();
    await tester.tap(find.text('The whole room'));
    await tester.pump();

    final selection = _markersOf(seen.last).single['selection'] as Map;
    expect(selection['selection_mode'], 'area');
    expect(selection['area_name'], 'living_room');
  });

  testWidgets('a room this house has nothing in falls back to the drag',
      (tester) async {
    await _pumpLive(tester, importedLiving(), [
      _light('light.kitchen', on: false, area: 'kitchen'),
    ]);
    await tester.tap(find.byType(Icon).first);
    await tester.pump();

    expect(find.textContaining('Drop a device on it'), findsOneWidget);
    expect(find.text('The whole room'), findsNothing);
  });

  testWidgets('and a long list says where the better tool is', (tester) async {
    await _pumpLive(tester, importedLiving(), [
      for (var i = 0; i < 9; i++)
        _light('light.$i', on: false, area: 'living_room'),
    ]);
    await tester.tap(find.byType(Icon).first);
    await tester.pump();

    expect(find.textContaining('3 more'), findsOneWidget);
  });
}

// ── which six get offered ──────────────────────────────────────────────────

/// Only six of a room's devices fit the panel, so which six matters. A real
/// living room with thirty-one things in it led with "Holiday Lights 1" while
/// the ceiling light the marker plainly *is* sat off the end of the list.

void _bindOrderTests() {
  test('a shared word ranks a device up, and nothing else does', () {
    expect(nameAffinity('Living ceiling', 'Ceiling light'), 1);
    expect(nameAffinity('Living ceiling', 'Holiday Lights 1'), 0);
    // Short words are noise, not evidence: "the" in common means nothing.
    expect(nameAffinity('The lamp', 'The kettle'), 0);
    expect(nameAffinity(null, 'Anything'), 0);
  });

  testWidgets('the offer leads with the light the file was talking about',
      (tester) async {
    await _pumpLive(
      tester,
      {
        'plan': const HomePlan(rooms: [
          PlanRoom(name: 'Living Room', points: [
            PlanPoint(0, 0),
            PlanPoint(400, 0),
            PlanPoint(400, 400),
            PlanPoint(0, 400),
          ]),
        ]).toJson(),
        'markers': [
          const FloorPlanMarker(
            selection: unboundSelection,
            x: 0.5,
            y: 0.5,
            home: PlanPoint(200, 200),
            label: 'Living ceiling',
          ).toJson(),
        ],
      },
      [
        for (var i = 1; i <= 6; i++)
          _light('Holiday Lights $i', on: false, area: 'living_room'),
        _sensorIn('Ceiling light', 'living_room'),
      ],
    );
    await tester.tap(find.byType(Icon).first);
    await tester.pump();

    // Seven devices and only six slots: without the ranking the one the file
    // named is exactly the one that falls off.
    expect(find.text('Ceiling light'), findsOneWidget);
  });

  group('the flare', () {
    /// A one-room home with a lamp in the middle of it, as import leaves one.
    Map<String, dynamic> config({
      required Map<String, dynamic> selection,
      String? lightColour = 'FFE0B0',
      double? hx = 200,
    }) =>
        {
          'plan': {
            'rooms': [
              {
                'name': 'Living',
                'points': [
                  {'x': 0, 'y': 0},
                  {'x': 400, 'y': 0},
                  {'x': 400, 'y': 300},
                  {'x': 0, 'y': 300},
                ],
              },
            ],
            'furniture': [
              {
                'name': 'Ceiling',
                'x': 200,
                'y': 150,
                'w': 40,
                'd': 40,
                'light': true,
                if (lightColour != null)
                  'lc': int.parse('FF$lightColour', radix: 16),
              },
            ],
          },
          'markers': [
            {
              'selection': selection,
              'x': 0.5,
              'y': 0.5,
              if (hx != null) ...{'hx': hx, 'hy': 150.0},
            },
          ],
        };

    Map<String, dynamic> bound(String id) => {
          'selection_mode': 'manual',
          'device_ids': [id],
        };

    Finder flare() => find.descendant(
        of: find.byType(PlanFlare), matching: find.byType(CustomPaint));

    List<PlanPool> pools(WidgetTester tester) =>
        tester.widget<PlanFlare>(find.byType(PlanFlare)).pools;

    testWidgets('a lit lamp puts light on the floor of its own room',
        (tester) async {
      await _pump(
          tester, config(selection: bound('lamp')), [_light('lamp', on: true)]);
      // Clipped, because light does not cross walls.
      expect(
          flare(),
          paints
            ..clipPath()
            ..circle());
    });

    testWidgets('and the same lamp off puts none there', (tester) async {
      // The whole point: the plan looks like the house looks right now.
      await _pump(tester, config(selection: bound('lamp')),
          [_light('lamp', on: false)]);
      expect(flare(), isNot(paints..circle()));
    });

    testWidgets('a marker bound to nothing stays dark, however lit the room',
        (tester) async {
      // Honest rather than helpful: nobody has said what that lamp is yet, so
      // the plan does not pretend to know it is the one that came on.
      await _pump(
        tester,
        config(selection: const {'selection_mode': 'manual', 'device_ids': []}),
        [_light('lamp', on: true)],
      );
      expect(flare(), isNot(paints..circle()));
    });

    testWidgets('a sensor lights nothing, whatever it is reading',
        (tester) async {
      // A room lit by its own thermometer would be nonsense.
      await _pump(
          tester, config(selection: bound('temp')), [_sensor('temp', 21.5)]);
      expect(flare(), isNot(paints..circle()));
    });

    testWidgets('it burns the colour the file gave it', (tester) async {
      // The one place in this card where a colour does not come from the skin,
      // and it is right: a warm bulb in a paper shade is a fact about the
      // house, the same kind of fact as the colour of its floor.
      await _pump(
          tester, config(selection: bound('lamp')), [_light('lamp', on: true)]);
      expect(pools(tester).single.tint, const Color(0xFFFFE0B0));
    });

    testWidgets('and the skin\'s where the file said nothing', (tester) async {
      await _pump(tester, config(selection: bound('lamp'), lightColour: null),
          [_light('lamp', on: true)]);
      expect(pools(tester).single.tint, HcSkin.midnight.tokens.accent.active);
    });

    testWidgets('a lamp turned down spills less than one turned up',
        (tester) async {
      await _pump(tester, config(selection: bound('lamp')),
          [_light('lamp', on: true, brightnessPct: 10)]);
      expect(pools(tester).single.strength, closeTo(0.1, 0.001));
    });

    testWidgets('a room speaks for its brightest lamp, never its average',
        (tester) async {
      // One lamp at full and one off is a lit room, not a half-lit one.
      await _pump(
        tester,
        config(selection: const {
          'selection_mode': 'manual',
          'device_ids': ['a', 'b'],
        }),
        [
          _light('a', on: true, brightnessPct: 100),
          _light('b', on: false, brightnessPct: 0),
        ],
      );
      expect(pools(tester).single.strength, 1.0);
    });

    testWidgets('placing markers turns it off', (tester) async {
      // The wash already says the card is in a mode, and a designer moving
      // markers is looking at where they are, not at what the house is doing.
      await _pump(
          tester, config(selection: bound('lamp')), [_light('lamp', on: true)],
          entered: true, onConfigChanged: (_) {});
      expect(find.byType(PlanFlare), findsNothing);
    });

    testWidgets('a marker with no place in the home spills nothing',
        (tester) async {
      // A marker on a picture has no room to be in — the flare is the one
      // thing only an imported home can do.
      await _pump(tester, config(selection: bound('lamp'), hx: null),
          [_light('lamp', on: true)]);
      expect(flare(), isNot(paints..circle()));
    });

    testWidgets('a marker dragged off its lamp lights in the skin instead',
        (tester) async {
      // Past the tolerance the marker is about something else, and borrowing
      // the nearest lamp's colour would light a room from a lamp nobody
      // pointed at.
      await _pump(tester, config(selection: bound('lamp'), hx: 380),
          [_light('lamp', on: true)]);
      expect(pools(tester).single.tint, HcSkin.midnight.tokens.accent.active);
    });
  });
}

/// A device in an area, named — enough to rank, which is all these tests ask.
DeviceState _sensorIn(String id, String area) => DeviceState(
      id: id,
      name: id,
      pluginId: 'plugin.test',
      deviceType: 'light',
      state: const {'state': 'off', 'on': false},
      available: true,
      areaOverride: area,
    );
