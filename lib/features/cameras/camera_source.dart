/// Pure camera-source logic, with no browser imports, so it is testable on the
/// Dart VM. The widget that actually mounts an `<iframe>` or `<img>` lives in
/// `camera_view.dart` and depends on this.
library;

/// How a camera delivers its picture.
enum CameraTransport {
  /// A go2rtc stream, shown by embedding go2rtc's own `stream.html` in an
  /// iframe. This is the important trick: the embedded page runs at go2rtc's
  /// OWN origin, so its WebSocket back to go2rtc is same-origin and its Origin
  /// check passes — WebRTC works with no `api.origin` config at all. Mounting
  /// go2rtc's `<video-stream>` element in our own page instead runs at OUR
  /// origin, so its WebSocket is cross-origin and go2rtc answers 403. Same
  /// component, opposite result, entirely because of who is hosting it.
  go2rtc,

  /// A plain never-ending MJPEG image (a generic IP camera). The browser
  /// animates it natively; no negotiation, no iframe.
  mjpeg,

  /// A single still, re-fetched on a timer.
  imageRefresh,
}

CameraTransport transportFor(String sourceType) => switch (sourceType) {
      'go2rtc' || 'webrtc' || 'mse' || 'hls' => CameraTransport.go2rtc,
      'image_refresh' => CameraTransport.imageRefresh,
      _ => CameraTransport.mjpeg,
    };

/// The go2rtc embed URL to put in an iframe, from whatever form the camera URL
/// was entered in.
///
/// A person reaches for `stream.html` — it is the page they can already open in
/// a browser tab — so that is accepted as-is. But `api/ws?src=X` (the WebSocket
/// endpoint) and a bare `?src=X` on some other go2rtc page are the same stream
/// said differently, so those are rewritten to the embed page rather than
/// rejected. Returns the input unchanged if it is not recognisably go2rtc.
String go2rtcEmbedUrl(String url) {
  // Already the embed page.
  if (url.contains('/stream.html')) return url;

  // The WebSocket endpoint, or any other go2rtc path carrying ?src= — rewrite
  // the path to stream.html, keep host and the src query.
  final m =
      RegExp(r'^(https?://[^/]+)/[^?]*\?(.*\bsrc=[^&]+.*)$').firstMatch(url);
  if (m != null) {
    final src = RegExp(r'\bsrc=([^&]+)').firstMatch(m.group(2)!)?.group(1);
    if (src != null) return '${m.group(1)}/stream.html?src=$src';
  }
  return url;
}

/// The MJPEG still/stream URL for a go2rtc source, for the non-iframe path.
///
/// Returns null when the URL is not a recognisable go2rtc endpoint.
String? go2rtcMjpegUrl(String url) {
  final m =
      RegExp(r'^(https?)://([^/]+)/[^?]*\?(?:.*&)?src=([^&]+)').firstMatch(url);
  if (m == null) return null;
  return '${m.group(1)}://${m.group(2)}/api/stream.mjpeg?src=${m.group(3)}';
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
