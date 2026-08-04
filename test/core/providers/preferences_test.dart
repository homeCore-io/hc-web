import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/providers/active_sort_provider.dart';
import 'package:hc_web/core/providers/client_error_log_provider.dart';
import 'package:hc_web/core/providers/collapsed_groups_provider.dart';
import 'package:hc_web/core/providers/nav_prefs_provider.dart';
import 'package:hc_web/core/providers/room_collapse_provider.dart';
import 'package:hc_web/core/providers/thermostat_prefs_provider.dart';
import 'package:hc_web/core/providers/time_display_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the locally-stored UI preferences must keep doing.
///
/// These eight providers are the last `StateNotifier`s in the app and are next
/// to be ported to `Notifier` (see `core/docs/riverpod-legacy-migration-plan.md`).
/// They had no tests at all, which is the wrong state to start a migration in:
/// every one of them shares a pattern the compiler cannot check — construct
/// with a default, load asynchronously from `SharedPreferences`, assign `state`
/// if still mounted, write through on mutation — and all of it is invisible to
/// `flutter analyze`.
///
/// The assertions that matter most are the **key literals**. These keys are
/// live in browsers today. Renaming one, or changing the type it is stored
/// under, is indistinguishable from resetting that preference: the app reads
/// nothing, silently falls back to its default, and reports no error anywhere.
/// So the keys are spelled out here as strings rather than imported from the
/// providers — importing the constant would happily follow a rename and prove
/// nothing.
///
/// Written deliberately against the *current* `StateNotifier` implementation.
/// The port must leave this file untouched; if it needs editing, behaviour
/// changed.

/// The `_load()` in each constructor is fire-and-forget across an async gap and
/// nothing exposes when it lands, so tests poll for the value they expect.
/// A failure here shows up as a timeout returning the default, which reads the
/// same as "the key did not match" — check the key first.
Future<void> _settleUntil(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// Give a pending `_load()` every chance to run, for the cases that assert a
/// value did *not* change. Waiting on `getInstance()` first means the store is
/// initialised and any `_load()` continuation is already queued behind it.
Future<void> _settle() async {
  await SharedPreferences.getInstance();
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// One locally-persisted preference, described well enough to test generically.
class _Pref {
  const _Pref({
    required this.name,
    required this.key,
    required this.read,
    required this.fallback,
    required this.seed,
    required this.loaded,
    required this.mutate,
    required this.afterMutation,
    required this.readBack,
    required this.written,
  });

  /// Human label for test names.
  final String name;

  /// The `SharedPreferences` key, written out as a literal on purpose.
  final String key;

  /// Reads the provider's current value. A closure rather than the provider
  /// itself: Riverpod 3 does not export a public supertype the eight share.
  final Object? Function(ProviderContainer) read;

  /// What the provider must expose when the key is absent.
  final Object? fallback;

  /// A value planted in storage, in the exact type the app stores it as.
  final Object seed;

  /// What the provider must expose once [seed] has loaded.
  final Object? loaded;

  /// Applies one user-level change, awaiting the write-through.
  final Future<void> Function(ProviderContainer) mutate;

  /// What the provider must expose after [mutate].
  final Object? afterMutation;

  /// Pulls the raw stored value back out, under [key].
  final Object? Function(SharedPreferences) readBack;

  /// What [readBack] must return after [mutate] — matched loosely for lists,
  /// whose order is an implementation detail of `Set.toList()`.
  final Object written;
}

final _prefs = <_Pref>[
  _Pref(
    name: 'active-first sort on Home',
    key: 'home_sort_active_first',
    read: (c) => c.read(activeSortProvider),
    fallback:
        true, // never chosen means on: the handful of lit devices is the story
    seed: false,
    loaded: false,
    // Starts at the default `true`, so the first toggle turns it off.
    mutate: (c) => c.read(activeSortProvider.notifier).toggle(),
    afterMutation: false,
    readBack: (p) => p.getBool('home_sort_active_first'),
    written: false,
  ),
  _Pref(
    name: 'collapsed section groups',
    key: 'collapsed_groups',
    read: (c) => c.read(collapsedGroupsProvider),
    fallback: <String>{}, // absent means expanded, so a new group is never folded
    seed: <String>['devices:kitchen', 'scenes:kitchen'],
    loaded: {'devices:kitchen', 'scenes:kitchen'},
    mutate: (c) =>
        c.read(collapsedGroupsProvider.notifier).toggle('devices:hall'),
    afterMutation: {'devices:hall'},
    readBack: (p) => p.getStringList('collapsed_groups'),
    written: <String>['devices:hall'],
  ),
  _Pref(
    name: 'nav rail visible',
    key: 'nav_rail_visible',
    read: (c) => c.read(navRailVisibleProvider),
    fallback: true,
    seed: false,
    loaded: false,
    mutate: (c) => c.read(navRailVisibleProvider.notifier).toggle(),
    afterMutation: false,
    readBack: (p) => p.getBool('nav_rail_visible'),
    written: false,
  ),
  _Pref(
    name: 'nav rail expanded',
    key: 'nav_rail_expanded',
    read: (c) => c.read(navRailExpandedProvider),
    fallback: false, // collapsed to icons is the quieter resting state
    seed: true,
    loaded: true,
    mutate: (c) => c.read(navRailExpandedProvider.notifier).set(true),
    afterMutation: true,
    readBack: (p) => p.getBool('nav_rail_expanded'),
    written: true,
  ),
  _Pref(
    name: 'landing route',
    key: 'landing_route',
    read: (c) => c.read(landingRouteProvider),
    fallback: '/',
    seed: '/pages/kitchen-dash',
    loaded: '/pages/kitchen-dash',
    mutate: (c) => c.read(landingRouteProvider.notifier).set('/pages/wall'),
    afterMutation: '/pages/wall',
    readBack: (p) => p.getString('landing_route'),
    written: '/pages/wall',
  ),
  _Pref(
    name: 'collapsed rooms on Home',
    key: 'home_rooms_collapsed',
    read: (c) => c.read(roomCollapseProvider),
    fallback: <String>{},
    seed: <String>['kitchen', 'garage'],
    loaded: {'kitchen', 'garage'},
    mutate: (c) => c.read(roomCollapseProvider.notifier).toggle('attic'),
    afterMutation: {'attic'},
    readBack: (p) => p.getStringList('home_rooms_collapsed'),
    written: <String>['attic'],
  ),
  _Pref(
    name: 'thermostats shown large',
    key: 'thermostat_large',
    read: (c) => c.read(thermostatLargeProvider),
    fallback: <String>{}, // every thermostat starts compact
    seed: <String>['thermostat.hall'],
    loaded: {'thermostat.hall'},
    mutate: (c) => c
        .read(thermostatLargeProvider.notifier)
        .setLarge('thermostat.den', true),
    afterMutation: {'thermostat.den'},
    readBack: (p) => p.getStringList('thermostat_large'),
    written: <String>['thermostat.den'],
  ),
  _Pref(
    name: 'UTC time display',
    key: 'time_display_utc',
    read: (c) => c.read(timeUtcProvider),
    fallback: false, // local time unless asked otherwise
    seed: true,
    loaded: true,
    mutate: (c) => c.read(timeUtcProvider.notifier).toggle(),
    afterMutation: true,
    readBack: (p) => p.getBool('time_display_utc'),
    written: true,
  ),
];

Matcher _matches(Object? expected) {
  if (expected is List) return unorderedEquals(expected);
  if (expected is Set) return unorderedEquals(expected);
  return equals(expected);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('with nothing stored', () {
    for (final pref in _prefs) {
      test('${pref.name} falls back to its default', () async {
        SharedPreferences.setMockInitialValues({});
        final c = ProviderContainer();
        addTearDown(c.dispose);

        // Reading constructs the notifier, which is what kicks off `_load()`.
        expect(pref.read(c), _matches(pref.fallback));

        // And the load must not move it. An absent key is "never chosen", not
        // "chosen to be empty" — the distinction the defaults are built on.
        await _settle();
        expect(pref.read(c), _matches(pref.fallback),
            reason: 'the load overwrote the default for ${pref.key}');
      });
    }
  });

  group('with a value already stored', () {
    for (final pref in _prefs) {
      test('${pref.name} loads it from "${pref.key}"', () async {
        SharedPreferences.setMockInitialValues({pref.key: pref.seed});
        final c = ProviderContainer();
        addTearDown(c.dispose);

        await _settleUntil(() {
          final v = pref.read(c);
          return v is Set
              ? v.length == (pref.loaded as Set).length
              : v == pref.loaded;
        });
        expect(pref.read(c), _matches(pref.loaded),
            reason: 'nothing was read back from "${pref.key}" — has the key '
                'or its stored type changed?');
      });
    }
  });

  group('a change writes through', () {
    for (final pref in _prefs) {
      test('${pref.name} persists under "${pref.key}"', () async {
        SharedPreferences.setMockInitialValues({});
        final c = ProviderContainer();
        addTearDown(c.dispose);

        // Let the initial load land first, so the mutation is applied to the
        // settled value rather than racing it.
        pref.read(c);
        await _settle();

        await pref.mutate(c);
        expect(pref.read(c), _matches(pref.afterMutation));

        final store = await SharedPreferences.getInstance();
        expect(pref.readBack(store), _matches(pref.written),
            reason: 'nothing landed under "${pref.key}" in the expected type');
      });
    }
  });

  test('a stored preference survives a reload', () async {
    // The whole point of these providers: a fresh container is a fresh page
    // load, and it must come back to what the last one left behind.
    SharedPreferences.setMockInitialValues({});

    final first = ProviderContainer();
    first.read(timeUtcProvider);
    await _settle();
    await first.read(timeUtcProvider.notifier).toggle();
    expect(first.read(timeUtcProvider), true);
    first.dispose();

    final second = ProviderContainer();
    addTearDown(second.dispose);
    await _settleUntil(() => second.read(timeUtcProvider) == true);
    expect(second.read(timeUtcProvider), true, reason: 'the reload lost it');
  });

  test('the keys the app writes are exactly these', () async {
    // A rename shows up here as a diff rather than as a preference that quietly
    // stops being remembered. If this fails, existing browsers are about to
    // lose whatever moved.
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);

    for (final pref in _prefs) {
      pref.read(c);
    }
    await _settle();
    for (final pref in _prefs) {
      await pref.mutate(c);
    }

    final store = await SharedPreferences.getInstance();
    expect(
      store.getKeys(),
      unorderedEquals(<String>{
        'home_sort_active_first',
        'collapsed_groups',
        'nav_rail_visible',
        'nav_rail_expanded',
        'landing_route',
        'home_rooms_collapsed',
        'thermostat_large',
        'time_display_utc',
      }),
    );
  });

  group('set-valued preferences', () {
    test('toggling twice returns to empty rather than accumulating', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(roomCollapseProvider);
      await _settle();

      final n = c.read(roomCollapseProvider.notifier);
      await n.toggle('kitchen');
      expect(c.read(roomCollapseProvider), {'kitchen'});
      await n.toggle('kitchen');
      expect(c.read(roomCollapseProvider), isEmpty);

      final store = await SharedPreferences.getInstance();
      expect(store.getStringList('home_rooms_collapsed'), isEmpty,
          reason: 'the removal did not reach storage');
    });

    test('the collapsed-groups namespacing keeps sections independent',
        () async {
      // "Kitchen" in Devices and "Kitchen" in Scenes must collapse separately;
      // the namespacing is the only thing keeping them apart.
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(collapsedGroupsProvider);
      await _settle();

      await c.read(collapsedGroupsProvider.notifier).toggle('devices:kitchen');
      expect(c.read(collapsedGroupsProvider), {'devices:kitchen'});
      expect(
          c.read(collapsedGroupsProvider).contains('scenes:kitchen'), isFalse);
    });

    test('setLarge(false) removes without disturbing the others', () async {
      SharedPreferences.setMockInitialValues({
        'thermostat_large': <String>['thermostat.hall', 'thermostat.den'],
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settleUntil(() => c.read(thermostatLargeProvider).length == 2);

      await c
          .read(thermostatLargeProvider.notifier)
          .setLarge('thermostat.hall', false);
      expect(c.read(thermostatLargeProvider), {'thermostat.den'});
    });
  });

  group('nav rail', () {
    test('toggle flips whatever was loaded, not the default', () async {
      // The bug this guards: a toggle that reads the default instead of the
      // stored value silently un-does the user's saved choice on first click.
      SharedPreferences.setMockInitialValues({'nav_rail_visible': false});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _settleUntil(() => c.read(navRailVisibleProvider) == false);

      await c.read(navRailVisibleProvider.notifier).toggle();
      expect(c.read(navRailVisibleProvider), true);
    });

    test('visible and expanded are stored separately', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(navRailVisibleProvider);
      c.read(navRailExpandedProvider);
      await _settle();

      await c.read(navRailExpandedProvider.notifier).set(true);
      final store = await SharedPreferences.getInstance();
      expect(store.getBool('nav_rail_expanded'), true);
      expect(store.getBool('nav_rail_visible'), isNull,
          reason: 'expanding the rail wrote to the visibility key');
    });
  });

  group('client error log', () {
    // In-memory only — the one provider of the eight with no persistence, and
    // the only one with a size bound to get wrong.
    test('starts empty and keeps what it is given, oldest first', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(clientErrorLogProvider), isEmpty);

      final n = c.read(clientErrorLogProvider.notifier);
      n.add(_entry('GET', '/api/devices', 500));
      n.add(_entry('POST', '/api/rules', 422));
      final log = c.read(clientErrorLogProvider);
      expect(log.map((e) => e.url), ['/api/devices', '/api/rules']);
      expect(log.first.statusCode, 500);
    });

    test('caps at 100 entries and drops the oldest', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(clientErrorLogProvider.notifier);
      for (var i = 0; i < 150; i++) {
        n.add(_entry('GET', '/api/$i', 500));
      }

      final log = c.read(clientErrorLogProvider);
      expect(log.length, 100);
      // 0..49 evicted, 50..149 kept — a ring buffer, not a truncation.
      expect(log.first.url, '/api/50');
      expect(log.last.url, '/api/149');
    });

    test('clear empties it', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(clientErrorLogProvider.notifier);
      n.add(_entry('GET', '/api/devices', 500));
      n.clear();
      expect(c.read(clientErrorLogProvider), isEmpty);
    });
  });
}

ApiErrorEntry _entry(String method, String url, int? status) => ApiErrorEntry(
      timestamp: DateTime.utc(2026, 8, 4, 12),
      method: method,
      url: url,
      statusCode: status,
      body: 'boom',
    );
