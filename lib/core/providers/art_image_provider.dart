import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/homecore_image.dart';
import 'auth_provider.dart';

/// How the now-playing card should load artwork.
///
/// Core's art proxy is an authenticated route, and a browser sends no
/// `Authorization` header when it loads an `<img>` — so the plain
/// `Image.network` this replaced worked only where core accepts the source IP
/// instead of a token, which is the LAN on port 8080 and nowhere else.
///
/// It is a provider rather than a global because the token belongs to the
/// session: nothing in the design layer should be able to reach one, and this
/// way the card takes a way to load an image rather than a way to authenticate.
final artImageProvider = Provider<ImageProvider Function(String deviceId)>(
  (ref) {
    final client = ref.watch(homecoreClientProvider);
    return (deviceId) => HomecoreImage.art(deviceId, client);
  },
);
