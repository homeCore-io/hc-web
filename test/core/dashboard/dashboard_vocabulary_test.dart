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
  /// **Not every editor is a config field.** `card_members.dart` edits `add`
  /// and `remove` for the four selection widgets, as a section of its own with
  /// a device list you tick — a `WidgetConfigField` could not have been that.
  /// Reading a bare `configFields` scan as the whole answer reports those eight
  /// as gaps, which is wrong and was: the first version of this test did, and
  /// the reason string beside them claimed the inspector edited only the rule.
  /// So editors outside the config form are declared here.
  test('every field core describes is one the editor offers', () {
    // Fields with an editor that is not a config field, and where it lives.
    const elsewhere = {
      'add': 'card_members.dart',
      'remove': 'card_members.dart',
      // Every widget carries it, and no widget declares it as a config field:
      // an action belongs to all of them, so it has a section of its own.
      'on_tap': 'card_inspector.dart, the WHEN TAPPED section',
    };

    // Real gaps. Each is a setting a document can carry and this app cannot
    // change, with what is lost written beside it. The list can only shrink.
    const known = {
      // An event feed can be narrowed to event types or to devices. The form
      // offers neither, so a feed narrowed elsewhere widens the moment it is
      // saved here.
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
        if (offered.contains(name)) continue;
        if (elsewhere.containsKey(name)) continue;
        if (known.contains(id)) continue;
        gaps.add(id);
      }
    }

    expect(
      gaps,
      isEmpty,
      reason: 'core validates these fields and this editor has no control for '
          'them, so a document written elsewhere carries settings this app '
          'silently cannot change. Add the control; if it is not a config '
          'field, name it in `elsewhere`; if it is a real gap, add it to '
          '`known` with what is lost meanwhile.',
    );
  });

  /// Which fields name something in the house — one answer, core's.
  ///
  /// This is what makes a page shareable: an export has to know which values
  /// are ids so it can replace them with a label. A client that worked that out
  /// from field names would miss the field a new widget added, and the page
  /// would travel carrying somebody else's hardware.
  test('this app agrees with core about what points at a device', () {
    const kinds = {
      'device': WidgetConfigKind.deviceRef,
      'devices': WidgetConfigKind.deviceRefs,
      'scene': WidgetConfigKind.sceneRef,
    };
    final disagreements = <String>[];

    for (final w in widgets) {
      final type = w['type'] as String;
      final descriptor = WidgetRegistry.lookup(type);
      if (descriptor == null) continue;
      for (final f in (w['fields'] as List).cast<Map<String, dynamic>>()) {
        final declared = kinds[f['reference']];
        if (declared == null) continue;
        final field = descriptor.configFields
            .where((c) => c.name == f['name'])
            .firstOrNull;
        // A field core marks as a reference and the editor does not offer at
        // all is covered by the coverage test above; here we only care that
        // the ones it DOES offer agree about what they point at.
        if (field == null) continue;
        if (field.kind != declared) {
          disagreements.add('$type.${f['name']}: core says ${f['reference']}, '
              'this app offers ${field.kind.name}');
        }
      }
    }

    expect(
      disagreements,
      isEmpty,
      reason: 'a reference this app fills from the wrong list is a wire that '
          'cannot resolve, and one it does not know is a device id that '
          'survives being shared.',
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
