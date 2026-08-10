import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/pages/page_background.dart';

/// What a page sits on.
///
/// John: *"background image for the page that everything sits on top of with
/// configurable blur."*
///
/// The claims worth pinning are the two that make it usable rather than
/// decorative. **Blur and dim apply to the image and not to the cards** — a
/// blurred dashboard is a broken dashboard, and the difference between this and
/// a frosted window is which layer the filter sits on. And **a page with no
/// background is untouched**, down to the widget tree, because every dashboard
/// saved before this has none.

/// A 1×1 transparent PNG for every request.
///
/// `Image.network` really does reach for the network in a widget test, where
/// Flutter's default client refuses everything — so the load fails
/// asynchronously and lands on whichever test happens to be running when it
/// does. That is why these passed one at a time and failed together.
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
      WidgetTester tester, DashboardBackground? background) async {
    await tester.pumpWidget(MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: PageBackground(
          background: background,
          child: const Text('a card'),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('no background leaves the page exactly as it was',
      (tester) async {
    await pump(tester, null);
    expect(find.text('a card'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(PageBackground), matching: find.byType(Stack)),
        findsNothing,
        reason: 'not an empty layer — no layer. Every dashboard saved before '
            'this has no background, and none of them should grow one.');
  });

  testWidgets('an empty address is the same as none', (tester) async {
    await pump(tester, const DashboardBackground(blur: 20, dim: 0.5));
    expect(
        find.descendant(
            of: find.byType(PageBackground), matching: find.byType(Stack)),
        findsNothing,
        reason: 'a blur with nothing to blur is a filter over the skin');
  });

  testWidgets('an image goes behind the content', (tester) async {
    await pump(tester, const DashboardBackground(image: 'http://x/y.jpg'));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('a card'), findsOneWidget);
  });

  testWidgets('the blur is over the image, not over the cards', (tester) async {
    // The whole difference between a background and a frosted window. If the
    // filter sat above the content, the dashboard would be the thing out of
    // focus.
    await pump(
        tester, const DashboardBackground(image: 'http://x/y.jpg', blur: 12));
    expect(find.byType(BackdropFilter), findsOneWidget);

    // Scoped to this widget's own Stack — Material contributes others.
    final stack = tester.widget<Stack>(find.descendant(
        of: find.byType(PageBackground), matching: find.byType(Stack)));
    expect(stack.children.last, isA<Positioned>(),
        reason: 'the page content is the top layer, so it paints after every '
            'filter below it');
    expect(
        find
            .descendant(
                of: find.byType(BackdropFilter), matching: find.text('a card'))
            .evaluate(),
        isEmpty,
        reason: 'and the cards are not inside the filter — a blurred dashboard '
            'is a broken dashboard');
  });

  testWidgets('dim uses the skin, so a light skin stays light', (tester) async {
    // Dimming towards black would make every skin the same skin at 60%.
    await pump(
        tester, const DashboardBackground(image: 'http://x/y.jpg', dim: 0.5));
    final scrim = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .where((b) => b.color.a > 0.4 && b.color.a < 0.6)
        .toList();
    expect(scrim, isNotEmpty);
    expect(scrim.first.color.r, HcSkin.midnight.tokens.surface.base.r);
  });

  group('the value', () {
    test('clamps what a hand-edited document can ask for', () {
      final wild = DashboardBackground.fromJson(
          const {'image': 'x', 'blur': 900, 'dim': 40});
      expect(wild.blur, 40);
      expect(wild.dim, 1);
      final negative = DashboardBackground.fromJson(
          const {'image': 'x', 'blur': -3, 'dim': -1});
      expect(negative.blur, 0);
      expect(negative.dim, 0);
    });

    test('round-trips, and omits an image it does not have', () {
      const bg = DashboardBackground(image: 'http://x/y.jpg', blur: 8, dim: .3);
      expect(DashboardBackground.fromJson(bg.toJson()), bg);
      expect(
          const DashboardBackground().toJson().containsKey('image'), isFalse);
    });

    test('a dashboard without one serialises as it always did', () {
      final page = DashboardDefinition(
        id: 'k',
        name: 'K',
        description: null,
        ownerUserId: 'u',
        visibility: DashboardVisibility.private,
        tags: const [],
        icon: 'grid',
        isDefault: false,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        layouts: const [],
        widgets: const [],
      );
      expect(page.toJson().containsKey('background'), isFalse,
          reason: 'nothing to migrate, and no diff on a page nobody styled');
    });
  });
}
