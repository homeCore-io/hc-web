import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/features/dashboard/dashboard_view_page.dart';

/// The default dashboard on a live HomeCore, captured from `GET /dashboards`.
/// Note the `house_status_hero` — a type core ships and the old Dart enum never
/// had.
const _liveDashboard = {
  'id': 'dashboard_e557c862671746b4b2c4db3447b28758',
  'name': 'Overview',
  'owner_user_id': 'u1',
  'visibility': 'private',
  'icon': 'home',
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
  'sections': [],
  'widgets': [
    {
      'id': 'house_status',
      'type': 'house_status_hero',
      'title': 'House Status',
      'refresh_policy': 'live',
      'config': {
        'layout': 'wide',
        'systems': ['lighting', 'climate', 'security'],
      },
    },
    {
      'id': 'tile_1',
      'type': 'device_tile',
      'title': 'Lamp',
      'refresh_policy': 'live',
      'config': {
        'selection_mode': 'manual',
        'device_ids': ['lamp']
      },
    },
  ],
  'layouts': [
    {
      'breakpoint': 'desktop',
      'columns': 12,
      'row_height': 150.0,
      'gap': 12.0,
      'placements': [
        {'widget_id': 'house_status', 'x': 0, 'y': 0, 'w': 12, 'h': 3},
        {'widget_id': 'tile_1', 'x': 0, 'y': 3, 'w': 3, 'h': 1},
      ],
    }
  ],
};

void main() {
  setUp(() {
    WidgetRegistry.reset();
    registerBuiltinDashboardWidgets();
  });

  group('the bug this replaced', () {
    test('house_status_hero is no longer silently turned into markdown', () {
      // The old model did `_enumByName(..., fallback: markdown)`, so core's own
      // hero card — on the *default* dashboard — parsed as a markdown widget.
      // Saving would then have written it back as one, destroying it.
      final dash = DashboardDefinition.fromJson(
        Map<String, dynamic>.from(_liveDashboard),
      );

      final hero = dash.widgets.firstWhere((w) => w.id == 'house_status');
      expect(hero.type, 'house_status_hero');
      expect(hero.type, isNot('markdown'));

      // And the client now actually knows how to draw it.
      expect(WidgetRegistry.knows('house_status_hero'), isTrue);
    });

    test('an unknown type survives a decode → encode round trip untouched', () {
      // A card from a newer core, or from a plugin this build has never seen.
      final json = {
        'id': 'w1',
        'type': 'some_future_card',
        'title': 'Mystery',
        'refresh_policy': 'live',
        'config': {'anything': 42},
      };

      final model =
          DashboardWidgetModel.fromJson(Map<String, dynamic>.from(json));
      expect(model.type, 'some_future_card');

      final out = model.toJson();
      expect(out['type'], 'some_future_card');
      expect(out['config'], {'anything': 42});
    });
  });

  group('registry', () {
    test('every built-in card is registered', () {
      for (final type in [
        'house_status_hero',
        'device_grid',
        'device_list',
        'device_tile',
        'stat_summary',
        'mode_chips',
        'scene_row',
        'event_feed',
        'history_chart',
        'media_player',
        'camera_video',
        'web_embed',
        'markdown',
        'dashboard_link',
      ]) {
        expect(WidgetRegistry.knows(type), isTrue, reason: '$type is missing');
      }
    });

    test('a plugin can contribute a card without touching this app', () {
      // The whole point. No enum to edit, no switch to extend.
      WidgetRegistry.register(
        WidgetDescriptor(
          type: pluginWidgetType,
          title: 'Solar production',
          icon: Icons.solar_power,
          builder: (context, args) => const Text('from a plugin'),
        ),
      );

      expect(WidgetRegistry.knows(pluginWidgetType), isTrue);
      expect(
        WidgetRegistry.all.map((d) => d.title),
        contains('Solar production'),
      );
    });

    test('an unregistered type resolves to null, not to a wrong card', () {
      expect(WidgetRegistry.lookup('nope'), isNull);
    });
  });

  group('client-side validation mirrors core', () {
    // Core rejects the *entire dashboard* on the first invalid widget, so a
    // single bad card would otherwise lose everything else the user just edited.
    String? check(String type, Map<String, dynamic> config) =>
        WidgetRegistry.lookup(type)!.validate?.call(config);

    test('a history chart needs a device and an attribute', () {
      expect(check('history_chart', {}), isNotNull);
      expect(check('history_chart', {'device_id': 'd'}), isNotNull);
      expect(
        check('history_chart', {'device_id': 'd', 'attribute': 'on'}),
        isNull,
      );
    });

    test('a device card needs a selection mode core recognises', () {
      expect(check('device_grid', {}), isNotNull);
      expect(check('device_grid', {'selection_mode': 'wat'}), isNotNull);
      expect(check('device_grid', {'selection_mode': 'manual'}), isNull);
    });

    test('area selection needs an area', () {
      expect(check('device_grid', {'selection_mode': 'area'}), isNotNull);
      expect(
        check(
            'device_grid', {'selection_mode': 'area', 'area_name': 'Kitchen'}),
        isNull,
      );
    });

    test('markdown needs text, a camera needs a source and a url', () {
      expect(check('markdown', {}), isNotNull);
      expect(check('markdown', {'markdown': '# hi'}), isNull);

      expect(check('camera_video', {'url': 'http://x'}), isNotNull);
      expect(
        check('camera_video', {'source_type': 'mjpeg', 'url': 'http://x'}),
        isNull,
      );
    });

    test('an unknown card is not judged — core is the authority', () {
      final errors = WidgetRegistry.validateAll(
        {'w1': {}},
        {'w1': 'some_future_card'},
      );
      expect(errors, isEmpty);
    });

    test('validateAll reports one message per offending card', () {
      final errors = WidgetRegistry.validateAll(
        {
          'good': {'markdown': 'hi'},
          'bad': {},
        },
        {'good': 'markdown', 'bad': 'markdown'},
      );
      expect(errors.keys, ['bad']);
    });
  });

  group('layout normalization uses the shared engine', () {
    test('the live dashboard round-trips and stays legal', () {
      final dash = DashboardDefinition.fromJson(
        Map<String, dynamic>.from(_liveDashboard),
      );

      final layout = normalizeDashboardLayout(
        dash.layoutFor(DashboardBreakpoint.desktop),
        dash.widgets,
      );

      expect(layout.placements, hasLength(2));
      for (final p in layout.placements) {
        expect(p.x + p.w, lessThanOrEqualTo(layout.columns));
        expect(p.x, greaterThanOrEqualTo(0));
        expect(p.y, greaterThanOrEqualTo(0));
      }
    });

    test('overlapping placements are repaired rather than sent to core', () {
      final dash = DashboardDefinition.fromJson({
        ...Map<String, dynamic>.from(_liveDashboard),
        'layouts': [
          {
            'breakpoint': 'desktop',
            'columns': 12,
            'row_height': 150.0,
            'gap': 12.0,
            'placements': [
              {'widget_id': 'house_status', 'x': 0, 'y': 0, 'w': 12, 'h': 3},
              // Sitting right on top of the hero.
              {'widget_id': 'tile_1', 'x': 0, 'y': 0, 'w': 3, 'h': 1},
            ],
          }
        ],
      });

      final layout = normalizeDashboardLayout(
        dash.layoutFor(DashboardBreakpoint.desktop),
        dash.widgets,
      );

      final a =
          layout.placements.firstWhere((p) => p.widgetId == 'house_status');
      final b = layout.placements.firstWhere((p) => p.widgetId == 'tile_1');
      final overlap = a.x < b.x + b.w &&
          a.x + a.w > b.x &&
          a.y < b.y + b.h &&
          a.y + a.h > b.y;
      expect(overlap, isFalse);
    });
  });
}
