import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/plugin_render.dart';
import 'package:hc_web/core/dashboard/vocabulary.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';

/// What this build cannot do about the core in front of it.
///
/// The compile-time test (`dashboard_vocabulary_test.dart`) compares against a
/// COMMITTED fixture, which only helps if somebody ran the sync script. Nobody
/// will always remember, and a user pointing this app at a newer core would
/// otherwise just find that some cards draw as nothing, with no explanation.
DashboardVocabularyDoc _doc(Map<String, dynamic> json) =>
    DashboardVocabularyDoc.fromJson(json);

void main() {
  setUp(() {
    WidgetRegistry.reset();
    registerBuiltinDashboardWidgets();
  });

  test('agreeing with core is silent', () {
    final drift = DashboardDrift.between(_doc({
      'widgets': [
        {'type': 'markdown', 'fields': []}
      ],
      'elements': [
        for (final kind in kDrawableElementKinds) {'kind': kind}
      ],
    }));
    expect(drift.isEmpty, isTrue);
    expect(drift.total, 0);
  });

  test('a card core knows and this app does not is reported', () {
    final drift = DashboardDrift.between(_doc({
      'widgets': [
        {'type': 'markdown', 'fields': []},
        {'type': 'thermostat_wheel', 'fields': []},
      ],
    }));
    expect(drift.unknownWidgets, ['thermostat_wheel']);
    expect(drift.isNotEmpty, isTrue);
  });

  test('a required field the editor cannot fill is reported', () {
    final drift = DashboardDrift.between(_doc({
      'widgets': [
        {
          'type': 'markdown',
          'fields': [
            {'name': 'markdown', 'type': 'string', 'required': true},
            {'name': 'ceiling_height', 'type': 'integer', 'required': true},
          ],
        }
      ],
    }));
    // The serious one: the editor can build a card core refuses, and core
    // rejects the whole dashboard on the first bad widget.
    expect(drift.unfillableFields, ['markdown.ceiling_height']);
  });

  test('a conditional required field is not drift', () {
    // `area_name` is required for a room card and meaningless for a manual
    // one. Core skips it the same way, and reporting it would name a card that
    // saves perfectly well.
    final drift = DashboardDrift.between(_doc({
      'widgets': [
        {
          'type': 'markdown',
          'fields': [
            {
              'name': 'ceiling_height',
              'type': 'integer',
              'required': true,
              'when': {'field': 'mode', 'equals': 'room'},
            },
          ],
        }
      ],
    }));
    expect(drift.unfillableFields, isEmpty);
  });

  test('the fields of an unknown card are not listed as well', () {
    // Listing every field of a card this app cannot draw at all would bury the
    // one line that matters under a dozen that follow from it.
    final drift = DashboardDrift.between(_doc({
      'widgets': [
        {
          'type': 'thermostat_wheel',
          'fields': [
            {'name': 'device_id', 'type': 'string', 'required': true},
          ],
        }
      ],
    }));
    expect(drift.unknownWidgets, ['thermostat_wheel']);
    expect(drift.unfillableFields, isEmpty);
  });

  test('an instrument this build cannot draw is reported', () {
    final drift = DashboardDrift.between(_doc({
      'elements': [
        {'kind': 'gauge'},
        {'kind': 'sparkline'},
      ],
    }));
    expect(drift.undrawableElements, ['sparkline']);
  });

  test('a card this app offers that core has never heard of is not drift', () {
    // Core accepts an unknown `type` on purpose — that is what lets a plugin
    // card exist without a core release — so a client ahead of its core is the
    // supported case, not a broken one.
    final drift = DashboardDrift.between(_doc(const {'widgets': []}));
    expect(drift.isEmpty, isTrue);
  });
}
