import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/design/components/hc_surface.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/page_grid.dart';

/// A card that reacts to its device.
///
/// The model tests say what a condition *answers*; this says the answer reaches
/// the paint. Colour rather than properties, because a variant that resolved
/// correctly and was then thrown away by the renderer is exactly the failure
/// worth catching, and every property assertion on it would pass.
DeviceState _door(bool open) => DeviceState(
      id: 'door',
      pluginId: 'p',
      available: true,
      state: {'open': open},
    );

DashboardWidgetModel _card() => const DashboardWidgetModel(
      id: 'a',
      type: 'markdown',
      title: 'A',
      refreshPolicy: DashboardRefreshPolicy.passive,
      config: {
        'markdown': 'x',
        'style': {
          'tint': 'raised',
          'variants': [
            {
              'when': {
                'DeviceState': {
                  'device_id': 'door',
                  'attribute': 'open',
                  'value': true,
                }
              },
              'style': {'tint': 'danger'},
            }
          ],
        },
      },
    );

Future<Color?> _tintWith(
  WidgetTester tester,
  DeviceState? Function(String)? lookup,
) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(800, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(MaterialApp(
    theme: hcTheme(HcSkin.midnight, reduceMotion: true),
    home: Scaffold(
      body: PageGrid(
        items: const [GridItem(id: 'a', x: 0, y: 0, w: 4, h: 2)],
        widgetsById: {'a': _card()},
        columns: 12,
        rowHeight: 120,
        gap: 12,
        editing: false,
        deviceLookup: lookup,
      ),
    ),
  ));
  await tester.pumpAndSettle();

  return tester
      .widgetList<HcSurface>(find.descendant(
        of: find.byKey(const ValueKey('a')),
        matching: find.byType(HcSurface),
      ))
      .first
      .tint;
}

void main() {
  testWidgets('the card takes the variant when the house matches',
      (tester) async {
    final closed = await _tintWith(tester, (id) => _door(false));
    final open = await _tintWith(tester, (id) => _door(true));

    expect(open, isNotNull);
    expect(open, isNot(closed),
        reason: 'the open door has to reach the paint, not just the model');
  });

  testWidgets('no house to ask means the base style, not the variant',
      (tester) async {
    // Offline is not "every door is open". A page that went red the moment it
    // lost the connection would be lying about the house rather than about
    // itself.
    final closed = await _tintWith(tester, (id) => _door(false));
    final unknown = await _tintWith(tester, null);
    expect(unknown, closed);
  });
}
