import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/assets_api.dart';
import 'package:hc_web/core/providers/assets_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/settings/assets_page.dart';

/// The page that makes deletion possible, and safe enough to offer.
///
/// Nothing in core reference-counts and nothing auto-deletes, which is the
/// right call — counting is the half that removes something still in use the
/// moment the count is wrong. The cost of that call is paid here: this is the
/// only place that says what is stored, what it costs, and what would break.

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? _) => _Client();
}

final _png = Uint8List.fromList(<int>[
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, //
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, //
  0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1, //
  13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

class _Client implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request();
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Request implements HttpClientRequest {
  @override
  final HttpHeaders headers = _Headers();
  @override
  Future<HttpClientResponse> close() async => _Response();
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Response implements HttpClientResponse {
  @override
  int statusCode = HttpStatus.ok;
  @override
  int get contentLength => _png.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  final HttpHeaders headers = _Headers();
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(_png).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Headers implements HttpHeaders {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

AssetRef _asset(String id,
        {String name = 'wall.png',
        int size = 4096,
        String? group,
        String type = 'image/png'}) =>
    AssetRef(id: id, contentType: type, size: size, name: name, group: group);

Future<void> _pump(WidgetTester tester, List<AssetRef> assets) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      assetListProvider.overrideWith((ref) async => assets),
    ],
    child: MaterialApp(
      theme: hcThemeFromTokens(HcSkin.midnight.tokens),
      home: const AssetsPage(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => HttpOverrides.global = _NoNetwork());
  tearDownAll(() => HttpOverrides.global = null);

  testWidgets('an empty store says where files come from', (tester) async {
    // Nobody arrives here first — they arrive after uploading something — so
    // an empty page has to explain what would fill it.
    await _pump(tester, const []);
    expect(find.text('Nothing stored'), findsOneWidget);
    expect(find.textContaining('choose a file'), findsOneWidget);
  });

  testWidgets('it says what is stored and what it costs', (tester) async {
    await _pump(tester, [
      _asset('a' * 64, name: 'wall.png', size: 4096),
      _asset('b' * 64, name: 'Fraunces.ttf', size: 417300, type: 'font/ttf'),
    ]);
    expect(find.text('wall.png'), findsOneWidget);
    expect(find.text('Fraunces.ttf'), findsOneWidget);
    // The total is the number that answers "why is the disk full".
    // SectionLabel uppercases; the count and the total are one label.
    expect(find.textContaining('2 FILES'), findsOneWidget);
    expect(find.textContaining('412 KB'), findsOneWidget);
  });

  testWidgets('an unused asset says so, which is what makes it safe to remove',
      (tester) async {
    await _pump(tester, [_asset('a' * 64)]);
    expect(find.textContaining('nothing points at it'), findsOneWidget);
  });

  testWidgets('a group can be removed as a set', (tester) async {
    // The case the whole store was designed around: one floor plan import is
    // dozens of textures, and removing the plan should not mean hunting them.
    await _pump(tester, [
      _asset('a' * 64, group: 'plan-ground'),
      _asset('b' * 64, group: 'plan-ground'),
      _asset('c' * 64),
    ]);
    expect(find.text('UPLOADED TOGETHER'), findsOneWidget);
    expect(find.text('plan-ground'), findsOneWidget);
    expect(find.text('2 files'), findsOneWidget);
    expect(find.text('Delete all'), findsOneWidget);
  });

  testWidgets('no groups, no group section', (tester) async {
    await _pump(tester, [_asset('a' * 64)]);
    expect(find.text('UPLOADED TOGETHER'), findsNothing);
  });

  testWidgets('deleting asks first, and says what it will break',
      (tester) async {
    await _pump(tester, [_asset('a' * 64, name: 'wall.png')]);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Delete wall.png?'), findsOneWidget);
    expect(find.textContaining('Nothing points at it'), findsOneWidget);
    // Cancel leaves it alone — the dialog is a question, not a countdown.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('wall.png'), findsOneWidget);
  });
}
