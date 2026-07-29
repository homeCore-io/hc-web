import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/audit_api.dart';
import 'package:hc_web/core/api/homecore_client.dart';
import 'package:hc_web/core/providers/audit_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/admin/audit_page.dart';

/// Counts what the page actually asks for. The count is the point: a filter
/// derived from `DateTime.now()` inside `build` produces a different family key
/// every frame, so the page refetches forever and never leaves its spinner.
class _FakeAuditApi implements AuditApi {
  _FakeAuditApi(this.rows);

  final List<AuditEntry> rows;
  final calls = <AuditFilter>[];

  // `implements`, not `extends`: HomecoreClient's baseUrl is the relative
  // `/api/v1`, which Dio rejects outside the browser, so the real class cannot
  // be constructed in a VM test. The client is never touched here.
  @override
  HomecoreClient get client => throw UnimplementedError();

  @override
  Future<List<AuditEntry>> list(AuditFilter filter) async {
    calls.add(filter);
    return rows;
  }
}

AuditEntry _entry({
  required String event,
  String result = 'success',
  String actorLabel = 'admin',
  String actorType = 'user',
  Duration ago = const Duration(minutes: 5),
  Map<String, dynamic>? detail,
}) =>
    AuditEntry(
      id: 1,
      at: DateTime.now().toUtc().subtract(ago),
      actorType: actorType,
      actorLabel: actorLabel,
      eventType: event,
      result: result,
      detail: detail,
    );

Widget _host(_FakeAuditApi api) => ProviderScope(
      overrides: [
        auditApiProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        theme: hcTheme(HcSkin.midnight),
        home: const Scaffold(body: AuditPage()),
      ),
    );

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('asks the server once, not once per frame', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _FakeAuditApi([
      _entry(event: 'auth.login', result: 'denied', actorType: 'anonymous'),
      _entry(event: 'user.created', detail: {'username': 'john'}),
    ]);

    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    // One fetch. Before the fix this was unbounded — `pumpAndSettle` never
    // returned, because each build asked for a new `from` bound down to the
    // microsecond and started another request.
    expect(api.calls.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the rows it was given', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(_FakeAuditApi([
      _entry(event: 'auth.login', result: 'denied', actorType: 'anonymous'),
      _entry(event: 'api_key.created', detail: {'label': 'hc-cli'}),
    ])));
    await tester.pumpAndSettle();

    expect(find.text('Sign-in refused'), findsOneWidget);
    expect(find.text('Created API key “hc-cli”'), findsOneWidget);
    expect(find.textContaining('Today'), findsOneWidget);
    // The denied count reaches the header, which is the reason to look.
    expect(find.text('denied'), findsWidgets);
  });

  testWidgets('an empty log says so rather than spinning', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(_FakeAuditApi([])));
    await tester.pumpAndSettle();

    expect(find.text('No events recorded'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('changing the range refetches exactly once', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _FakeAuditApi([_entry(event: 'auth.login')]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    expect(api.calls.length, 1);

    await tester.tap(find.text('30 days'));
    await tester.pumpAndSettle();

    expect(api.calls.length, 2);
    expect(api.calls.last.from!.isBefore(api.calls.first.from!), isTrue);
  });

  testWidgets('filtering by class does not go back to the server',
      (tester) async {
    // Core matches `event_type` exactly, so a class filter cannot be a query —
    // it is applied to what the query already returned.
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _FakeAuditApi([
      _entry(event: 'auth.login'),
      _entry(event: 'user.created', detail: {'username': 'john'}),
    ]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();

    expect(api.calls.length, 1, reason: 'class filtering is client-side');
    expect(find.text('Created user “john”'), findsOneWidget);
    expect(find.text('Signed in'), findsNothing);
  });
}
