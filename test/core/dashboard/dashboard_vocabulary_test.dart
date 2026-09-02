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

  /// The same question, asked the other way — and the way that actually failed.
  ///
  /// The test above walks core's list and asks whether this app can draw each
  /// entry. That is the direction of the `house_status_hero` incident, and it
  /// is the direction that hurts *this* client's users.
  ///
  /// It is not the direction that drifted. Nineteen widget types accumulated
  /// here — the primitives, the drawings, the whole control row — and core had
  /// never heard of any of them. Nothing complained, because a client ahead of
  /// core breaks no card in front of anybody: core accepts an unknown `type` on
  /// purpose. What it breaks is the *next* client, and the promise that one
  /// question to `/dashboards/vocabulary` enumerates every card that exists
  /// here.
  ///
  /// So this asks the question that has no symptom until somebody else writes a
  /// client, or a page is exported, or a plugin wants to know what it may draw
  /// beside.
  test('every card this app can draw is one core has been told about', () {
    final declared = {for (final w in widgets) w['type'] as String};
    final undeclared = WidgetRegistry.all
        .map((d) => d.type)
        .where((t) => !declared.contains(t))
        .toList()
      ..sort();

    expect(
      undeclared,
      isEmpty,
      reason: 'this app draws these and no served vocabulary describes them, '
          'so a second client reading a page that uses one has nothing to go '
          'on. Declare them in hc-types/src/dashboard_vocabulary.rs, '
          'regenerate with UPDATE_DASHBOARD_VOCABULARY=1 cargo test -p '
          'hc-types, then run tool/sync-dashboard-vocabulary.sh. If core '
          'already knows, the fixture is simply stale.',
    );
  });

  /// A field this app offers that core has never been told about is not an
  /// error — `extra_fields` is true for every widget, and a client-side drawing
  /// preference rides along in exactly that space by design.
  ///
  /// The other way round is worth seeing. A field core validates and this
  /// editor cannot set is a setting a document carries and this app silently
  /// will not touch: open the card elsewhere, narrow it, open it here, save,
  /// and the narrowing is gone.
  ///
  /// The known ones are listed rather than tolerated. Every entry is a real
  /// gap with its consequence written beside it, and the list can only shrink.
  test('every field core describes is one the editor offers', () {
    const known = {
      // The selection exceptions. A selection is a rule plus the device it
      // does not reach and the one it reaches wrongly; the inspector still
      // edits only the rule.
      'device_grid.add', 'device_grid.remove',
      'device_list.add', 'device_list.remove',
      'device_tile.add', 'device_tile.remove',
      'media_player.add', 'media_player.remove',
      // An event feed can be narrowed to types or to devices. The form offers
      // neither, so a feed narrowed elsewhere widens the moment it is saved
      // here.
      'event_feed.types', 'event_feed.device_ids',
      // A chart's row cap. The form offers the timeframe and not this.
      'history_chart.limit',
    };

    final gaps = <String>[];
    for (final w in widgets) {
      final type = w['type'] as String;
      final descriptor = WidgetRegistry.lookup(type);
      if (descriptor == null) continue;

      final offered = {for (final f in descriptor.configFields) f.name};
      for (final f in (w['fields'] as List).cast<Map<String, dynamic>>()) {
        final name = f['name'] as String;
        final id = '$type.$name';
        if (!offered.contains(name) && !known.contains(id)) gaps.add(id);
      }
    }

    expect(
      gaps,
      isEmpty,
      reason: 'core validates these fields and this editor has no control for '
          'them, so a document written elsewhere carries settings this app '
          'silently cannot change. Add the control, or add the field to '
          '`known` above with what is lost meanwhile.',
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
