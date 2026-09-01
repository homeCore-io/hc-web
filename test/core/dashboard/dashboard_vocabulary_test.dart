import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/plugin_render.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';

/// The registry in `lib/features/dashboard/builtin_cards.dart` is this client's
/// answer to a question core also answers, and the two used to be able to
/// disagree in silence.
///
/// The incident is the one `test/features/automations/vocabulary_test.dart`
/// opens with, and it was a DASHBOARD widget: core grew `house_status_hero`,
/// shipped it on its own default dashboard, and this client had never heard of
/// it — so it coerced the card to `markdown` and would have saved it back as
/// one, destroying it. That day the *rule* vocabulary got a fixture and a test.
/// The dashboard one did not, and this is it.
///
/// The fixture is core's own snapshot of the table its validator EXECUTES —
/// `hc-types/src/dashboard_vocabulary.rs`, plus the element kinds from
/// `widget_descriptor.rs`. Never written by hand; refresh it with
/// `tool/sync-dashboard-vocabulary.sh`.
void main() {
  final vocabulary = jsonDecode(
    File('test/fixtures/dashboard-vocabulary.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  final widgets = (vocabulary['widgets'] as List).cast<Map<String, dynamic>>();

  setUp(() {
    WidgetRegistry.reset();
    registerBuiltinDashboardWidgets();
  });

  test('every widget type core validates is a card this app can draw', () {
    final missing = [
      for (final w in widgets)
        if (!WidgetRegistry.knows(w['type'] as String)) w['type'] as String,
    ];

    expect(
      missing,
      isEmpty,
      reason: 'core validates these types and this app has no descriptor for '
          'them, so a dashboard using one renders as an unknown card. Add a '
          'descriptor, or run tool/sync-dashboard-vocabulary.sh if the fixture '
          'is simply stale.',
    );
  });

  test('every required config field core enforces is one the editor can fill',
      () {
    // Conditional fields are skipped: `area_name` is required only when
    // `selection_mode` is `area`, and a form that demanded it unconditionally
    // would refuse to save a perfectly good manual card. Core skips them the
    // same way, in `validate_widget_config`.
    final gaps = <String>[];
    for (final w in widgets) {
      final type = w['type'] as String;
      final descriptor = WidgetRegistry.lookup(type);
      if (descriptor == null) continue;

      final known = {for (final f in descriptor.configFields) f.name};
      for (final f in (w['fields'] as List).cast<Map<String, dynamic>>()) {
        if (f['required'] != true) continue;
        if (f.containsKey('when')) continue;
        if (!known.contains(f['name'])) gaps.add("$type.${f['name']}");
      }
    }

    expect(
      gaps,
      isEmpty,
      reason: 'core rejects a card without these fields, and this app offers '
          'no way to set them — so the editor can build a card that core '
          'refuses, and the user loses the whole dashboard on save.',
    );
  });

  /// A capability claim, checked against core.
  ///
  /// When this test was written hc-web could not draw a `render` tree at all,
  /// and this was a tripwire that only asked whether somebody had *considered*
  /// each kind. `PluginRenderView` draws them now, so the list is
  /// [kDrawableElementKinds] and the claim is real.
  ///
  /// Both directions matter. A kind core advertises and this app cannot draw is
  /// a plugin card rendering as an empty rectangle; a kind this app claims and
  /// core does not advertise is a capability nothing will ever ask for, which
  /// is usually a typo.
  test('this app draws exactly the element kinds core advertises', () {
    final advertised = {
      for (final e in (vocabulary['elements'] as List? ?? const [])
          .cast<Map<String, dynamic>>())
        e['kind'] as String,
    };

    expect(
      advertised.difference(kDrawableElementKinds),
      isEmpty,
      reason: 'core advertises an element kind this client cannot draw. A '
          'plugin widget may use it, and the card renders as nothing. Teach '
          'PluginRenderView to draw it, then add it to kDrawableElementKinds.',
    );
    expect(
      kDrawableElementKinds.difference(advertised),
      isEmpty,
      reason: 'this app claims an element kind core does not advertise, so it '
          'is either a typo or a capability nothing will ever ask for.',
    );
  });
}
