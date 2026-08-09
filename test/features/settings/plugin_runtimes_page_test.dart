import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/homecore_client.dart';
import 'package:hc_web/core/api/plugin_runtimes_api.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/settings/plugin_runtimes_page.dart';

/// The approval screen is the one place in the plugin story where the operator
/// *is* the security. In open mode anyone reachable may ask to join; nothing is
/// granted until an administrator approves a request whose code matches the one
/// printed in that container's own logs.
///
/// So these tests are about the screen making that check hard to skip, not
/// about layout.

// `implements`, not `extends`: HomecoreClient's baseUrl is the relative
// `/api/v1`, which Dio rejects outside a browser.
class _FakeRuntimesApi implements PluginRuntimesApi {
  _FakeRuntimesApi(this.rows);

  List<PluginRuntimeSummary> rows;
  final approved = <String>[];
  final denied = <String>[];

  @override
  HomecoreClient get client => throw UnimplementedError();

  @override
  Future<List<PluginRuntimeSummary>> list() async => rows;

  @override
  Future<void> approve(String runtimeId) async => approved.add(runtimeId);

  @override
  Future<void> deny(String runtimeId, {String? reason}) async =>
      denied.add(runtimeId);

  @override
  Future<EnrollToken> issueToken() async => EnrollToken(token: 'hc_sk_test');
}

PluginRuntimeSummary _runtime({
  required String id,
  required String status,
  String? code,
  String hostname = 'pyhost-01',
  String? pluginId,
}) =>
    PluginRuntimeSummary(
      runtimeId: id,
      status: status,
      kind: 'python',
      abi: 'cp312-manylinux_2_28',
      arch: 'x86_64',
      hostVersion: '0.1.0',
      sdkVersion: '0.2.0',
      hostname: hostname,
      networkMode: 'host',
      createdAt: '2026-08-09T00:00:00Z',
      code: code,
      sourceIp: '10.0.10.42',
      pluginId: pluginId,
    );

Widget _host(_FakeRuntimesApi api) => ProviderScope(
      overrides: [
        pluginRuntimesApiProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        theme: hcTheme(HcSkin.midnight),
        home: const Scaffold(body: PluginRuntimesPage()),
      ),
    );

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  Future<void> pumpWith(WidgetTester tester, _FakeRuntimesApi api) async {
    await tester.binding.setSurfaceSize(const Size(1300, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(api));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the code and the instruction to compare it are both on screen',
      (tester) async {
    final api = _FakeRuntimesApi([
      _runtime(id: 'rt-abc', status: 'pending', code: '865-981'),
    ]);
    await pumpWith(tester, api);

    expect(find.text('865-981'), findsOneWidget);
    // The words matter as much as the code: an operator who does not know to
    // compare it will approve whatever asked.
    expect(
      find.textContaining('Compare this code'),
      findsOneWidget,
      reason: 'the check has to be stated, not implied',
    );
    expect(find.textContaining('deny'), findsOneWidget);
  });

  testWidgets('approving sends only that runtime', (tester) async {
    final api = _FakeRuntimesApi([
      _runtime(id: 'rt-one', status: 'pending', code: '111-111'),
      _runtime(id: 'rt-two', status: 'pending', code: '222-222'),
    ]);
    await pumpWith(tester, api);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve').first);
    await tester.pump();

    expect(api.approved, ['rt-one']);
    expect(api.denied, isEmpty);
  });

  testWidgets('denying does not approve', (tester) async {
    final api = _FakeRuntimesApi([
      _runtime(id: 'rt-one', status: 'pending', code: '111-111'),
    ]);
    await pumpWith(tester, api);

    await tester.tap(find.widgetWithText(TextButton, 'Deny').first);
    await tester.pump();

    expect(api.denied, ['rt-one']);
    expect(api.approved, isEmpty);
  });

  /// An approved runtime is an ordinary plugin managed on the plugin page. The
  /// code is meaningless once resolved and must not linger as something that
  /// still looks like it needs answering.
  testWidgets('an approved runtime shows no code', (tester) async {
    final api = _FakeRuntimesApi([
      _runtime(
        id: 'rt-live',
        status: 'approved',
        pluginId: 'plugin.python-rtlive',
      ),
    ]);
    await pumpWith(tester, api);

    expect(find.textContaining('Compare this code'), findsNothing);
    expect(find.text('plugin.python-rtlive'), findsOneWidget);
  });

  /// `[plugin_runtimes] enabled = false` makes the endpoints 404, and the API
  /// turns that into an empty list. The page must read as "nothing has joined"
  /// rather than as a failure.
  testWidgets('no runtimes is a calm empty state, not an error',
      (tester) async {
    final api = _FakeRuntimesApi([]);
    await pumpWith(tester, api);

    expect(find.textContaining('No runtimes have joined'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
