import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/vocabulary.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/providers/dashboard_vocabulary_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/dashboard/dashboard_drift_notice.dart';

Future<void> _pump(
  WidgetTester tester,
  DashboardVocabularyDoc? vocabulary,
) async {
  WidgetRegistry.reset();
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(500, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(ProviderScope(
    overrides: [
      dashboardVocabularyProvider.overrideWith((ref) async => vocabulary),
    ],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: const Scaffold(
        body: SingleChildScrollView(child: DashboardDriftNotice()),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a core that could not be asked says nothing', (tester) async {
    // "I could not check" is not a finding. Turning it into a banner would fire
    // on every deployment that has not been upgraded yet.
    await _pump(tester, null);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('agreeing with core says nothing', (tester) async {
    await _pump(
      tester,
      DashboardVocabularyDoc.fromJson(const {
        'widgets': [
          {'type': 'markdown', 'fields': []}
        ],
      }),
    );
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('a card this app cannot draw is named, once opened',
      (tester) async {
    await _pump(
      tester,
      DashboardVocabularyDoc.fromJson(const {
        'widgets': [
          {'type': 'thermostat_wheel', 'fields': []}
        ],
      }),
    );

    expect(find.textContaining('1 card this app cannot draw'), findsOneWidget);
    // Collapsed until asked: the headline is the whole message for most
    // people, and the list of type names is for whoever is going to fix it.
    expect(find.text('thermostat_wheel'), findsNothing);

    await tester.tap(find.textContaining('1 card this app cannot draw'));
    await tester.pumpAndSettle();
    expect(find.text('thermostat_wheel'), findsOneWidget);
  });

  testWidgets('a setting the editor cannot fill is the one that leads',
      (tester) async {
    // Two kinds of drift at once. The unfillable field wins the headline
    // because it is the only one that costs the user work: core rejects the
    // whole dashboard on the first bad widget, so a card built here takes every
    // other edit in the same sitting down with it.
    await _pump(
      tester,
      DashboardVocabularyDoc.fromJson(const {
        'widgets': [
          {'type': 'thermostat_wheel', 'fields': []},
          {
            'type': 'markdown',
            'fields': [
              {'name': 'ceiling_height', 'type': 'integer', 'required': true},
            ],
          },
        ],
      }),
    );

    expect(find.textContaining('refuse to save'), findsOneWidget);

    await tester.tap(find.textContaining('refuse to save'));
    await tester.pumpAndSettle();
    expect(find.text('markdown.ceiling_height'), findsOneWidget);
    // Still reported, just not leading.
    expect(find.text('thermostat_wheel'), findsOneWidget);
  });

  testWidgets('an instrument this app cannot draw is reported on its own',
      (tester) async {
    await _pump(
      tester,
      DashboardVocabularyDoc.fromJson(const {
        'elements': [
          {'kind': 'gauge'},
          {'kind': 'sparkline'},
        ],
      }),
    );
    expect(find.textContaining('1 instrument this app cannot draw'),
        findsOneWidget);
  });
}
