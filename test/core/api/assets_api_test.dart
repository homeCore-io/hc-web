import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/assets_api.dart';

/// The address a picker stores.
///
/// Everything about assets rests on one property: the id is the sha256 of the
/// bytes, so it is unguessable, and that is what lets core serve the read with
/// no token. These pin the client's half of that — the shape of the address and
/// what it will offer to upload.

void main() {
  group('the address', () {
    test('is relative, so it survives the way the house is reached', () {
      // Absolute would bake in whichever origin the browser happened to be on
      // when the file was chosen: correct at home, wrong through nginx, wrong
      // again over remote access.
      expect(assetUrl('a' * 64), '/api/v1/assets/${'a' * 64}');
      expect(assetUrl('a' * 64).startsWith('/'), isTrue);
      expect(assetUrl('a' * 64).contains('://'), isFalse);
    });

    test('is recognisable, so a manager can tell ours from a pasted one', () {
      expect(isAssetUrl('/api/v1/assets/${'0' * 64}'), isTrue);
      expect(isAssetUrl('  /api/v1/assets/${'f' * 64}  '), isTrue);
      expect(isAssetUrl('https://example.test/wall.png'), isFalse);
      expect(isAssetUrl('/api/v1/assets/short'), isFalse);
      expect(isAssetUrl('/api/v1/assets/${'A' * 64}'), isFalse,
          reason: 'core writes lowercase hex and nothing else');
      expect(isAssetUrl('/api/v1/assets/${'0' * 64}/../x'), isFalse);
    });
  });

  group('what it will offer to upload', () {
    test('the types core actually accepts, and no others', () {
      // If these drift apart the user picks a file and gets a 415 back, which
      // is a worse way to find out than the picker not offering it.
      expect(contentTypeFor('wall.png'), 'image/png');
      expect(contentTypeFor('WALL.JPG'), 'image/jpeg');
      expect(contentTypeFor('plan.svg'), 'image/svg+xml');
      expect(contentTypeFor('Fraunces.woff2'), 'font/woff2');
      expect(contentTypeFor('notes.txt'), isNull);
      expect(contentTypeFor('archive.sh3d'), isNull);
      expect(contentTypeFor('noextension'), isNull);
      expect(contentTypeFor('trailing.'), isNull);
    });

    test('a name with dots resolves on the last one', () {
      expect(contentTypeFor('my.floor.plan.png'), 'image/png');
    });

    test('the accept string is what a file input wants', () {
      expect(acceptFor(['png', 'svg']), '.png,.svg');
      expect(acceptFor(fontExtensions), '.ttf,.otf,.woff,.woff2');
    });

    test('every offered extension has a type, in both directions', () {
      for (final e in [...imageExtensions, ...fontExtensions]) {
        expect(assetContentTypes[e], isNotNull, reason: '$e has no type');
      }
      for (final e in assetContentTypes.keys) {
        expect([...imageExtensions, ...fontExtensions], contains(e),
            reason: '$e is typed but offered by nothing');
      }
    });
  });

  group('the cap', () {
    test('matches the one core enforces', () {
      // Stated here so the picker can refuse before the round trip; core still
      // enforces it, because a client is not a guard.
      expect(maxAssetBytes, 16 * 1024 * 1024);
    });

    test('sizes read the way a person would say them', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(417300), '408 KB');
      expect(formatBytes(16 * 1024 * 1024), '16.0 MB');
    });
  });

  group('what core sends back', () {
    test('a record becomes an address', () {
      final ref = AssetRef.fromJson({
        'id': 'b' * 64,
        'content_type': 'font/ttf',
        'size': 417300,
        'name': 'Inter-Medium.ttf',
        'group': 'plan-ground',
      });
      expect(ref.url, '/api/v1/assets/${'b' * 64}');
      expect(ref.group, 'plan-ground');
      expect(ref.size, 417300);
    });

    test('a response missing fields does not throw', () {
      // Never seen from our own core, but a decoder that throws takes the
      // upload down with it and the file is already stored by then.
      final ref = AssetRef.fromJson(const {});
      expect(ref.id, '');
      expect(ref.group, isNull);
    });
  });
}
