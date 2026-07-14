/// Pure camera-source logic, with no browser imports, so it is testable on the
/// Dart VM. The widget that actually mounts a `<video-stream>` or `<img>` lives
/// in `camera_view.dart` and depends on this.
library;

/// How a camera delivers its picture.
enum CameraTransport {
  /// go2rtc's negotiating element: WebRTC → MSE → MJPEG, best-first. The right
  /// choice for a security wall — sub-second latency when WebRTC lands.
  go2rtc,

  /// A plain never-ending MJPEG image (a generic IP camera, or a go2rtc that has
  /// not enabled cross-origin WebSockets). The browser animates it natively.
  mjpeg,

  /// A single still, re-fetched on a timer.
  imageRefresh,
}

CameraTransport transportFor(String sourceType) => switch (sourceType) {
      'go2rtc' || 'webrtc' || 'mse' || 'hls' => CameraTransport.go2rtc,
      'image_refresh' => CameraTransport.imageRefresh,
      _ => CameraTransport.mjpeg,
    };

/// The MJPEG URL a go2rtc `/api/ws?src=X` endpoint corresponds to.
///
/// go2rtc's WebSocket (WebRTC/MSE) enforces an Origin check and refuses a
/// cross-origin browser with 403 unless `api.origin` is configured. Its plain
/// HTTP `stream.mjpeg` does NOT — it serves any origin. So when the socket is
/// refused we can still show the camera, at MJPEG quality, with zero server
/// config. This derives that fallback URL from the stream endpoint.
///
/// Returns null when the URL is not a recognisable go2rtc ws endpoint — there is
/// then no fallback to invent, and guessing a path on a generic camera would
/// just 404.
String? go2rtcMjpegFallback(String wsUrl) {
  final match = RegExp(r'^(https?)://([^/]+)/api/ws\?(?:.*&)?src=([^&]+)')
      .firstMatch(wsUrl);
  if (match == null) return null;
  return '${match.group(1)}://${match.group(2)}/api/stream.mjpeg?src=${match.group(3)}';
}

/// The URL to fetch for a given frame of an image source.
///
/// A still must be re-fetched, and browsers cache stills hard; without the
/// buster the same frame is served forever and a live camera looks frozen — the
/// worst failure a security wall can have, because a frozen picture of a quiet
/// driveway is indistinguishable from a quiet driveway. A stream is fetched once
/// and left alone.
String cameraSrc(String url, String sourceType, int frame) {
  if (sourceType != 'image_refresh') return url;
  return '$url${url.contains('?') ? '&' : '?'}_=$frame';
}
