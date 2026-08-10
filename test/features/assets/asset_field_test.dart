import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/assets/asset_field.dart';

/// The field that finally has somewhere to put a file.
///
/// The design claim being pinned: **this is the same field it always was, plus
/// a button.** Every consumer stores a string the browser resolves, so pasting
/// an address must behave exactly as it did before assets existed — otherwise
/// adding the picker to four places at once would have been a migration rather
/// than an addition.

class _FakeImages extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? _) => _FakeClient();
}

final _png = Uint8List.fromList(<int>[
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, //
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, //
  0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1, //
  13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

class _FakeClient implements HttpClient {
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
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeRequest();
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHeaders();
  @override
  Future<HttpClientResponse> close() async => _FakeResponse();
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse implements HttpClientResponse {
  @override
  int statusCode = HttpStatus.ok;
  @override
  int get contentLength => _png.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  final HttpHeaders headers = _FakeHeaders();
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
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => HttpOverrides.global = _FakeImages());
  tearDownAll(() => HttpOverrides.global = null);

  Future<void> pump(
    WidgetTester tester, {
    required String value,
    required ValueChanged<String> onChanged,
    List<String>? kinds,
    bool preview = true,
    String? label,
  }) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: hcThemeFromTokens(HcSkin.midnight.tokens),
        home: Scaffold(
          body: AssetField(
            value: value,
            onChanged: onChanged,
            label: label,
            preview: preview,
            kinds: kinds ?? const ['png', 'jpg'],
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('a pasted address reaches the caller, unchanged and trimmed',
      (tester) async {
    // The behaviour that existed before there was anywhere to upload, and the
    // reason nothing stored had to change.
    String? got;
    await pump(tester, value: '', onChanged: (v) => got = v);

    await tester.enterText(
        find.byType(TextField), '  https://house.lan/wall.png  ');
    expect(got, 'https://house.lan/wall.png');
  });

  testWidgets('it starts showing what it was given', (tester) async {
    await pump(tester, value: '/api/v1/assets/${'a' * 64}', onChanged: (_) {});
    expect(find.text('/api/v1/assets/${'a' * 64}'), findsOneWidget);
  });

  testWidgets('there is a way to choose a file', (tester) async {
    // The whole point of the change. Tapping it opens a browser file dialog,
    // which a widget test cannot drive — that this is here and enabled is the
    // part worth pinning.
    await pump(tester, value: '', onChanged: (_) {});
    expect(find.text('Choose'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('an empty field offers no clear, a filled one does',
      (tester) async {
    await pump(tester, value: '', onChanged: (_) {});
    expect(find.byIcon(Icons.close), findsNothing);

    String? got;
    await pump(tester, value: 'https://x/y.png', onChanged: (v) => got = v);
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(got, '',
        reason: 'clearing sets the empty string, not null-ish junk');
  });

  testWidgets('a preview appears only when there is something to preview',
      (tester) async {
    await pump(tester, value: '', onChanged: (_) {});
    expect(find.byType(Image), findsNothing);

    await pump(tester, value: 'https://house.lan/wall.png', onChanged: (_) {});
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a font field shows no thumbnail', (tester) async {
    // Nothing a font could show at 38px, and an error icon beside every font
    // would read as a problem.
    await pump(tester,
        value: '/api/v1/assets/${'c' * 64}',
        onChanged: (_) {},
        kinds: const ['ttf'],
        preview: false);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Choose'), findsOneWidget);
  });

  testWidgets('the label is the caller\'s', (tester) async {
    await pump(tester, value: '', onChanged: (_) {}, label: 'Picture');
    expect(find.text('Picture'), findsOneWidget);
  });
}
