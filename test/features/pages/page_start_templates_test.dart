import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/dashboards_api.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/providers/auth_provider.dart';
import 'package:hc_web/core/providers/dashboards_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/pages/page_screen.dart';

/// The pages somebody already composed, where a person looks for them.
///
/// They were behind a different button on the dashboards screen, so the natural
/// path — New page — could not reach them at all: looking for the room template
/// he had just been told about, John found the three built-in starts instead.
/// Two lists of "how do I begin a page" is one too many, and the one you find
/// is the one that gets used.
class _FakeApi extends DashboardsApi {
  _FakeApi(this.templates) : super.fake();
  final List<DashboardDefinition> templates;
  @override
  Future<List<DashboardDefinition>> listTemplates() async => templates;
}

DashboardDefinition _template(String id, String name, String? blurb) =>
    DashboardDefinition(
      id: id,
      name: name,
      description: blurb,
      ownerUserId: 'me',
      visibility: DashboardVisibility.private,
      tags: const [],
      icon: 'grid',
      isDefault: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      widgets: const [],
      layouts: const [],
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<DashboardDefinition> templates,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      dashboardsApiProvider.overrideWithValue(_FakeApi(templates)),
      // The templates provider asks who is signed in so it can fall back to
      // the built-in set on an older core. Neither matters here.
      currentUserProvider.overrideWith((ref) async => {'id': 'me'}),
    ],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: EmptyPageStarts(
          editing: true,
          rooms: const [],
          onStart: (kind, {String? room, String? label}) {},
          onTemplate: (_) {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the built-in starts and the composed pages are one list',
      (tester) async {
    await _pump(tester, templates: [
      _template('starter_room', 'A room, composed', 'Arrives unwired.'),
      _template('starter_house', 'House', 'Every room at once.'),
    ]);
    // The three that were always here.
    expect(find.text('A wall display'), findsOneWidget);
    expect(find.text('Blank'), findsOneWidget);
    // And the ones core serves, in the same panel.
    expect(find.text('A room, composed'), findsOneWidget);
    expect(find.text('House'), findsOneWidget);
    expect(find.text('Or start from a page'), findsOneWidget);
  });

  testWidgets('a template says what it is for', (tester) async {
    await _pump(tester, templates: [
      _template('starter_room', 'A room, composed', 'Arrives unwired.'),
    ]);
    expect(find.text('Arrives unwired.'), findsOneWidget);
  });

  testWidgets('an older core that serves none says nothing', (tester) async {
    // Silent rather than an error: a banner about a feature nobody asked for
    // yet is worse than an absence.
    await _pump(tester, templates: const []);
    expect(find.text('Or start from a page'), findsNothing);
    expect(find.text('Blank'), findsOneWidget, reason: 'the starts remain');
  });
}
