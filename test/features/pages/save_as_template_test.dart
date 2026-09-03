import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/device_slot.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';

/// A page becoming a starting point.
///
/// Templates were five documents compiled into core, read-only, so every good
/// page anybody designed stayed a one-off. This is the write path.
///
/// The transform itself lives in core — sharing a design and saving one are the
/// same operation with different destinations, so they are the same function
/// there. What this covers is the client's half: the flag survives the wire,
/// the two lists stay separate, and a template says what it is.

DashboardDefinition page({
  bool isTemplate = false,
  List<DashboardWidgetModel> widgets = const [],
}) =>
    DashboardDefinition(
      id: 'dashboard_1',
      name: 'Office',
      description: null,
      ownerUserId: 'u1',
      visibility: DashboardVisibility.private,
      tags: const [],
      icon: 'grid',
      isDefault: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      layouts: const [],
      widgets: widgets,
      isTemplate: isTemplate,
    );

DashboardWidgetModel toggle(String id, String title, String deviceId) =>
    DashboardWidgetModel(
      id: id,
      type: 'toggle',
      title: title,
      refreshPolicy: DashboardRefreshPolicy.live,
      config: {'device_id': deviceId},
    );

void main() {
  setUp(() {
    WidgetRegistry.reset();
    registerBuiltinDashboardWidgets();
  });

  group('the flag on the wire', () {
    test('a page that predates templates reads as a page', () {
      final read = DashboardDefinition.fromJson({
        'id': 'dashboard_1',
        'name': 'Office',
        'owner_user_id': 'u1',
        'icon': 'grid',
      });
      expect(read.isTemplate, isFalse);
    });

    test('a page writes no key, so nothing saved changes', () {
      expect(page().toJson().containsKey('template'), isFalse);
    });

    test('a template says so, and says it the way core reads it', () {
      final json = page(isTemplate: true).toJson();
      expect(json['template'], true);
      expect(DashboardDefinition.fromJson(json).isTemplate, isTrue);
    });

    test('and stating the default explicitly leaves no trail', () {
      // Both directions have to agree, or a document grows a `false` it then
      // carries around forever.
      final read = DashboardDefinition.fromJson({
        'id': 'dashboard_1',
        'name': 'Office',
        'owner_user_id': 'u1',
        'icon': 'grid',
        'template': false,
      });
      expect(read.isTemplate, isFalse);
      expect(read.toJson().containsKey('template'), isFalse);
    });
  });

  group('the house comes out of it', () {
    // The client's copy of the rule, used by nothing on the wire path — core
    // does the transform — but this is what a starting point *is*, and the two
    // implementations agreeing is the only reason a template exported here can
    // be imported there.
    test('a device id becomes a slot named for the widget', () {
      final lamp = toggle('lamp', 'Desk lamp', 'hue_0x1234');
      expect(unwireAll(lamp, null)['device_id'], 'slot:Desk lamp');
    });

    test('a slot is left alone, so saving twice is not saving twice', () {
      final already = toggle('lamp', 'Desk lamp', 'slot:Desk lamp');
      expect(unwireAll(already, null)['device_id'], 'slot:Desk lamp');
    });

    test('everything that is not the house is untouched', () {
      const lamp = DashboardWidgetModel(
        id: 'lamp',
        type: 'toggle',
        title: 'Desk lamp',
        refreshPolicy: DashboardRefreshPolicy.live,
        config: {
          'device_id': 'hue_0x1234',
          'style': {'filled': false},
          'group': 'Panel',
        },
      );
      final out = unwireAll(lamp, null);
      expect(out['style'], {'filled': false});
      expect(out['group'], 'Panel');
    });
  });

  group('a template is a dashboard in every other respect', () {
    test('it keeps its widgets, its layouts and its name', () {
      final source = page(widgets: [toggle('lamp', 'Desk lamp', 'hue_1')]);
      final template = source.copyWith(isTemplate: true);
      expect(template.widgets, source.widgets);
      expect(template.layouts, source.layouts);
      expect(template.name, 'Office');
    });

    test('and the page it came from is not converted', () {
      // `copyWith` is a copy, which is the whole shape of this feature:
      // somebody who carries on using the page they just saved a template of
      // is the common case, not the exception.
      final source = page();
      expect(source.copyWith(isTemplate: true).isTemplate, isTrue);
      expect(source.isTemplate, isFalse);
    });
  });
}
