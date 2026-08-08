import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/app.dart';
import 'package:hc_web/core/api/homecore_client.dart';
import 'package:hc_web/core/models/hc_event.dart';
import 'package:hc_web/core/providers/auth_provider.dart';
import 'package:hc_web/core/providers/events_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signing out, through the app's own router.
///
/// **This test could not be written before now.** `lib/app.dart` holds the
/// router, the auth redirect and the notifier that drives it, and importing it
/// from a VM test failed at compile time: two leaf files reached
/// `dart:js_interop` and `dart:ui_web` directly, so the whole graph above them
/// was web-only. `routing_contract_test.dart` says as much and pins go_router's
/// behaviour against a reproduction of the app's shapes instead.
///
/// The consequence was not theoretical. The half that had no test is exactly
/// the half that broke: Sign out cleared the session and the app stayed on the
/// page, because nothing ever checked that it went anywhere.

/// Signed in until told otherwise.
///
/// Overriding the notifier keeps this about the router's reaction rather than
/// about a network call — but note it overrides `build` only. `logout` is the
/// real one, because `logout` is the thing under test.
class _FakeAuth extends AuthNotifier {
  @override
  Future<bool> build() async => true;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Signed in, with the live event socket silenced and a client Dio accepts.
  ///
  /// The pages the router lands on open a WebSocket against `Uri.base`, which
  /// is `http://:0` under the test binding — the page's business, not the
  /// router's, and letting it throw would drown the assertion. The client is
  /// the real one with an absolute base, because `logout` goes through it to
  /// clear the stored token and that clearing is half of what is under test.
  newContainer() => ProviderContainer(overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        eventsStreamProvider
            .overrideWith((ref) => const Stream<HcEvent>.empty()),
        homecoreClientProvider.overrideWith(
            (ref) => HomecoreClient(baseUrl: 'http://localhost/api/v1')),
      ]);

  /// Big enough for the house page to lay out. The default 800x600 overflows
  /// it by a mile, and an overflow exception during a routing assertion is
  /// noise that reads like a failure.
  Future<void> roomy(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  /// Unmount before the test ends.
  ///
  /// Several pages poll on a timer — device counts and plugin notices do not
  /// arrive over the websocket — and the test binding fails a test that leaves
  /// one pending. Replacing the tree lets their dispose cancel them.
  /// Unmount and tear the container down, inside the test body.
  ///
  /// Several things poll on a timer — device counts and plugin notices do not
  /// arrive over the websocket — and those timers belong to providers, not
  /// widgets. `addTearDown(container.dispose)` runs *after* the binding checks
  /// for pending timers, so the container has to go down here instead.
  Future<void> unmount(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    await tester.pump();
  }

  // The app's own root, not a bare MaterialApp.router. `HomecoreApp` is what
  // supplies the base skin to the routes that sit outside the shell — login is
  // one of them — so a hand-rolled host would land on a login page with no
  // tokens and fail for a reason that has nothing to do with signing out.
  Widget app(ProviderContainer container) => UncontrolledProviderScope(
        container: container,
        child: const HomecoreApp(),
      );

  testWidgets('signing out lands on the login page', (tester) async {
    await roomy(tester);
    final container = newContainer();

    await tester.pumpWidget(app(container));
    await tester.pumpAndSettle();

    final router = container.read(routerProvider);
    expect(router.state.matchedLocation, isNot('/login'),
        reason: 'a signed-in session should not start on the login page');

    await container.read(authProvider.notifier).logout();
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/login',
        reason: 'Sign out clears the session; if the router does not react the '
            'app sits on a page it is no longer entitled to show, and the '
            'button looks like it did nothing');
    await unmount(tester, container);
  });

  testWidgets('the session is actually cleared, not just navigated away from',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'flutter.jwt_token': 'stale',
      'flutter.refresh_token': 'stale-refresh',
    });
    await roomy(tester);
    final container = newContainer();

    await tester.pumpWidget(app(container));
    await tester.pumpAndSettle();
    await container.read(authProvider.notifier).logout();
    await tester.pumpAndSettle();

    // Landing on /login while the token survives in storage is the worse bug of
    // the two: the next reload signs you back in, and a shared tablet hands the
    // house to whoever picks it up next.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('jwt_token'), isNull);
    expect(prefs.getString('refresh_token'), isNull);
    await unmount(tester, container);
  });
}
