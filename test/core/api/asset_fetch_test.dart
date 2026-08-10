import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/asset_fetch.dart';
import 'package:hc_web/design/font_registry.dart';

/// The fetcher behind a custom font.
///
/// These exist because of a bug rather than a feature. `FontRegistry.fetch` is
/// injected so tests never reach the network — correct — but nothing outside
/// the tests ever injected anything, so the default stub stayed in place and
/// every `register` call returned false. The fonts UI shipped in 0.1.36 with a
/// fetcher that could not fetch, and no test noticed, because every test
/// supplied its own.
///
/// So the rule pinned first is the one that was broken: **something wires it**.

void main() {
  setUp(() => FontRegistry.instance.reset());
  tearDown(() => FontRegistry.instance.reset());

  group('wiring', () {
    test('the registry starts with a fetcher that cannot fetch', () async {
      expect(await FontRegistry.instance.fetch('http://x/f.ttf'), isNull,
          reason: 'the default is a stub, which is the safe default for tests '
              'and a silent failure for the app');
    });

    test('installing replaces it with the real one', () {
      installAssetFetch();
      expect(FontRegistry.instance.fetch, same(fetchAssetBytes),
          reason: 'the line missing from main.dart for a whole release');
    });
  });

  group('what a stored address resolves to', () {
    test('an absolute address is used as written', () {
      expect(resolveAssetUrl('http://10.0.10.150:8080/fonts/fraunces.ttf'),
          Uri.parse('http://10.0.10.150:8080/fonts/fraunces.ttf'));
      expect(resolveAssetUrl('https://house.lan/f.woff2'),
          Uri.parse('https://house.lan/f.woff2'));
    });

    test('a relative one resolves against the page, not against nothing', () {
      // The point of this: on the day core can store an asset, the same field
      // takes `/assets/…` and neither the skin document nor this code changes.
      expect(resolveAssetUrl('/assets/fraunces.ttf'),
          Uri.base.resolve('/assets/fraunces.ttf'));
    });

    test('surrounding space is not an address', () {
      expect(
          resolveAssetUrl('  http://x/f.ttf  '), Uri.parse('http://x/f.ttf'));
      expect(resolveAssetUrl('   '), isNull);
      expect(resolveAssetUrl(''), isNull);
    });
  });

  group('what it refuses', () {
    // No network in any of these: they are all rejected before a request.
    test('a scheme a browser should not be fetching a font over', () async {
      expect(await fetchAssetBytes('data:font/ttf;base64,AAAA'), isNull,
          reason: 'a font inlined into a skin document would bloat every read '
              'of it');
      expect(await fetchAssetBytes('file:///etc/passwd'), isNull);
      expect(await fetchAssetBytes('javascript:alert(1)'), isNull);
    });

    test('nothing at all', () async {
      expect(await fetchAssetBytes(''), isNull);
      expect(await fetchAssetBytes('   '), isNull);
    });
  });

  group('the contract it owes the registry', () {
    test('a refusal costs a typeface, not a house', () async {
      installAssetFetch();
      // file: is rejected without a request, so this exercises the whole path
      // from register() down and back without touching the network.
      expect(await FontRegistry.instance.register('Fraunces', 'file:///f.ttf'),
          isFalse);
      expect(FontRegistry.instance.has('Fraunces'), isFalse);
      expect(FontRegistry.instance.has('Inter'), isTrue,
          reason: 'the bundled faces are unaffected by a font that would not '
              'load');
    });
  });
}
