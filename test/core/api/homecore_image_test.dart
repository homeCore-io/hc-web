import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/homecore_client.dart';
import 'package:hc_web/core/api/homecore_image.dart';

/// Artwork through the authenticated client.
///
/// The bug this replaces: the card loaded `/api/v1/devices/{id}/media/art`
/// with `Image.network`, and a browser attaches no `Authorization` header to
/// an `<img>`. Core's art proxy is protected, so it answered on the LAN via
/// the source-IP whitelist and 401'd through nginx — and a 401 here draws the
/// "no artwork" placeholder, so it read as a speaker with no cover rather than
/// as a failure.

void main() {
  test('it asks for the device it was given, relative to the API base', () {
    // An absolute base only because dio rejects a relative one off-web; the
    // app itself runs on web, where '/api/v1' is the real setting.
    final image = HomecoreImage.art(
        'media.living_room', HomecoreClient(baseUrl: 'http://h/api/v1'));
    expect(image.path, '/devices/media.living_room/media/art');
    expect(image.path.startsWith('/api/v1'), isFalse,
        reason: 'the client already carries the base URL; repeating it here '
            'would ask for /api/v1/api/v1/…');
  });

  test('two providers for the same device are one cache key', () {
    // Providers are cache keys. If these compared unequal the card would
    // refetch the artwork on every rebuild.
    final dio = Dio();
    expect(HomecoreImage('/devices/a/media/art', dio),
        HomecoreImage('/devices/a/media/art', dio));
    expect(HomecoreImage('/devices/a/media/art', dio).hashCode,
        HomecoreImage('/devices/a/media/art', dio).hashCode);
    expect(
        HomecoreImage('/devices/a/media/art', dio) ==
            HomecoreImage('/devices/b/media/art', dio),
        isFalse);
  });

  test('it is an ImageProvider, so the card keeps its errorBuilder', () {
    // No artwork is normal — a radio stream, a paused speaker — and the card
    // already draws a fallback for it. Staying an ImageProvider is what keeps
    // that path working rather than replacing it with a broken image.
    expect(HomecoreImage('/x', Dio()), isA<ImageProvider>());
  });
}
