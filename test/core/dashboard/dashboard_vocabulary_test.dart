import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

  /// A tripwire rather than a capability claim.
  ///
  /// hc-web does not render a plugin widget's `render` tree yet, so this cannot
  /// honestly assert "we can draw all of these". What it can do is fail the
  /// moment core advertises a kind nobody here has considered — which is the
  /// decision that must not be made by nobody. When the portable render path
  /// lands, this list becomes the set it implements and the reason changes.
  test('core advertises no element kind this app has not considered', () {
    const considered = {
      'gauge',
      'shape',
      'text',
      'icon',
      'row',
      'column',
      'stack',
    };

    final advertised = {
      for (final e in (vocabulary['elements'] as List? ?? const [])
          .cast<Map<String, dynamic>>())
        e['kind'] as String,
    };

    expect(
      advertised.difference(considered),
      isEmpty,
      reason: 'core advertises an element kind this client has never weighed. '
          'A plugin widget may use it, and every client that cannot draw it '
          'renders that card as nothing. Decide, then add it here.',
    );
    expect(
      considered.difference(advertised),
      isEmpty,
      reason: 'this list names an element kind core no longer advertises, so '
          'it is either a typo or a capability nothing will ever ask for.',
    );
  });
}
