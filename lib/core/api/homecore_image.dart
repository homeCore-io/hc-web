import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'homecore_client.dart';

/// An image that goes through the authenticated client instead of the browser.
///
/// A browser attaches no `Authorization` header when it loads an `<img>`, so
/// `Image.network('/api/v1/…')` on a protected route works only where core
/// accepts the *source IP* instead of a token. Probed against the live house:
///
///     http://10.0.10.150:8080/api/v1/devices   200   ← IP whitelist
///     http://10.0.10.150:3001/api/v1/devices   401   ← through nginx
///
/// Album art is exactly that case. It has been loading with `Image.network`
/// against `/devices/{id}/media/art`, so it appears on the LAN over port 8080
/// and silently falls back to the "no artwork" placeholder through the front
/// door — which looks like a speaker with no cover, not like an auth failure.
///
/// Assets solved the same problem a different way: a public route with an
/// unguessable content-hash id. That reasoning does **not** transfer here. A
/// device id is short, meaningful and enumerable, so making the art proxy
/// public would let an unauthenticated caller walk the house and see what is
/// playing. The token is the right answer for this one.
///
/// Fetching through `dio` also inherits the client's 401-refresh-and-replay,
/// so artwork on a page left open overnight recovers with everything else
/// rather than being the one thing that stays broken until a reload.
class HomecoreImage extends ImageProvider<HomecoreImage> {
  const HomecoreImage(this.path, this.dio, {this.scale = 1.0});

  /// A device's artwork, by id. The path is relative to the client's base URL.
  factory HomecoreImage.art(String deviceId, HomecoreClient client) =>
      HomecoreImage('/devices/$deviceId/media/art', client.dio);

  /// Relative to the client's `baseUrl`, not an absolute address.
  final String path;
  final Dio dio;
  final double scale;

  @override
  Future<HomecoreImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<HomecoreImage>(this);

  @override
  ImageStreamCompleter loadImage(
    HomecoreImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: key.scale,
      debugLabel: key.path,
    );
  }

  Future<ui.Codec> _load(HomecoreImage key, ImageDecoderCallback decode) async {
    final res = await key.dio.get<List<int>>(
      key.path,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = res.data;
    if (data == null || data.isEmpty) {
      // Nothing playing, or a track with no artwork. Throwing here is what
      // reaches the caller's `errorBuilder`, which already draws the fallback —
      // so an absent cover stays a design decision rather than becoming a
      // broken image.
      throw StateError('no artwork for ${key.path}');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(
      Uint8List.fromList(data),
    ));
  }

  @override
  bool operator ==(Object other) =>
      other is HomecoreImage && other.path == path && other.scale == scale;

  @override
  int get hashCode => Object.hash(path, scale);

  @override
  String toString() => 'HomecoreImage($path)';
}
