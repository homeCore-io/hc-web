import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/app.dart';
import 'package:hc_web/core/api/homecore_client.dart';
import 'package:hc_web/core/models/hc_event.dart';
import 'package:hc_web/core/providers/auth_provider.dart';
import 'package:hc_web/core/providers/events_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Landing straight on a URL, before the app knows whether you are signed in.
///
/// **The bug this exists for.** `/#/pages/<id>` opened on a cold load sat on a
/// spinner forever: no error, no failed request, nothing in the console. The
/// same page opened instantly from inside the running app. It was read as a
/// bug about *which dashboard* — one whose owner was not a real user — and
/// carried as that for three days. Ownership had nothing to do with it. Any
/// deep link hung, on any page, including ones the user plainly owned.
///
/// The cause was that the router's redirect was `async`. It awaited
/// `authProvider.future` so the app would not flash the house before bouncing
/// to login — but `_RouterNotifier` fires on that *same* auth transition, so
/// go_router began a second redirect pass while the first was still suspended.
/// Both passes then completed and the router delivered neither: no route was
/// ever built. A warm navigation never awaits, which is exactly why the bug
/// only ever showed on the first load and looked like bad luck.
///
/// So the invariant is: **the redirect must not be asynchronous.** Everything
/// the decision needs is resolved by `appBootProvider` before the router is
/// constructed at all.
class _SlowAuth extends AuthNotifier {
  @override
  Future<bool> build() =>
      Future.delayed(const Duration(milliseconds: 20), () => true);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  newContainer() => ProviderContainer(overrides: [
        authProvider.overrideWith(_SlowAuth.new),
        eventsStreamProvider
            .overrideWith((ref) => const Stream<HcEvent>.empty()),
        homecoreClientProvider.overrideWith(
            (ref) => HomecoreClient(baseUrl: 'http://localhost/api/v1')),
      ]);

  Future<void> roomy(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  /// Unmount and tear the container down inside the test body — several
  /// providers poll on a timer, and the binding checks for pending timers
  /// before `addTearDown` would run.
  Future<void> unmount(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    await tester.pump();
  }

  Widget app(ProviderContainer container) => UncontrolledProviderScope(
        container: container,
        child: const HomecoreApp(),
      );

  testWidgets('a cold boot reaches a route once auth resolves', (tester) async {
    await roomy(tester);
    final container = newContainer();

    await tester.pumpWidget(app(container));

    // Auth has not answered yet. Nothing may have routed — but equally the app
    // must not have given up: the failure mode being pinned is a boot that
    // never resolves, so the assertion that matters is the one after settling.
    await tester.pump();

    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).state.matchedLocation,
      '/',
      reason: 'the router never delivered a route: an async redirect that is '
          'still awaiting when auth resolves races the refreshListenable, and '
          'the app sits on a spinner with nothing to show for it',
    );
    await unmount(tester, container);
  });

  testWidgets('the boot gate does not strand a signed-out session',
      (tester) async {
    await roomy(tester);
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(_SignedOut.new),
      eventsStreamProvider.overrideWith((ref) => const Stream<HcEvent>.empty()),
      homecoreClientProvider.overrideWith(
          (ref) => HomecoreClient(baseUrl: 'http://localhost/api/v1')),
    ]);

    await tester.pumpWidget(app(container));
    await tester.pumpAndSettle();

    expect(container.read(routerProvider).state.matchedLocation, '/login',
        reason: 'holding the app behind the gate must still end in a decision');
    await unmount(tester, container);
  });

  /// The invariant itself, read off the source.
  ///
  /// The behavioural tests above pin that a boot *ends* somewhere, but they run
  /// under `flutter_test`'s clock, where the two redirect passes may not
  /// interleave the way a browser's do — the deadlock was reproducible in
  /// Chrome and not here. So this reads `app.dart` the way
  /// `manage_routes_test.dart` reads it: the guarantee is structural, and a
  /// structural guarantee can be checked structurally.
  test('the router redirect is synchronous', () {
    final source = File('lib/app.dart').readAsStringSync();
    // Deliberately not anchored to a `{` body: an arrow-bodied
    // `redirect: (_, __) async => ...` is the same bug with different
    // punctuation, and a regex that only saw block bodies would wave it
    // through. The per-route redirects match too — they are synchronous, so
    // they simply pass, and checking them is free.
    final redirect = RegExp(r'redirect:\s*\([^)]*\)\s*(async\b)?')
        .allMatches(source)
        .toList();
    expect(redirect, isNotEmpty,
        reason: 'no top-level `redirect:` found — this test has gone stale '
            'against app.dart and is checking nothing');
    for (final match in redirect) {
      expect(
        match.group(1),
        isNull,
        reason: 'the router redirect is `async`. It must not be: an await here '
            'is suspended across the auth transition that `_RouterNotifier` '
            'fires on, go_router starts a second pass over the first, and no '
            'route is ever built — every deep link hangs on a cold load with '
            'no error. Resolve what you need in `appBootProvider` instead.',
      );
    }
  });
}

/// No session, resolved immediately.
class _SignedOut extends AuthNotifier {
  @override
  Future<bool> build() async => false;
}
