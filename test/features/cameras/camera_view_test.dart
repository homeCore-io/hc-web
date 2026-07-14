import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/features/cameras/camera_source.dart';

/// The browser-free half of the camera view. The half that needs a browser — the
/// actual decode of a cross-origin stream — cannot be tested in a headless
/// sandbox (a plain <img> loading a valid JPEG fires onerror there, which is an
/// environment limit, not the app), so it is verified by eye in a real browser.
/// This pins everything up to that line.
void main() {
  group('transport selection', () {
    test('go2rtc and its transports route to the negotiating element', () {
      for (final s in ['go2rtc', 'webrtc', 'mse', 'hls']) {
        expect(transportFor(s), CameraTransport.go2rtc, reason: s);
      }
    });

    test('a still is a still; everything else is a plain mjpeg image', () {
      expect(transportFor('image_refresh'), CameraTransport.imageRefresh);
      expect(transportFor('mjpeg'), CameraTransport.mjpeg);
      // An unknown type does not become a black rectangle — it is attempted as
      // an image, which either shows something or reports itself unreachable.
      expect(transportFor('whatever'), CameraTransport.mjpeg);
    });
  });

  group('the MJPEG fallback URL', () {
    // go2rtc's WebSocket refuses a cross-origin browser (403) unless api.origin
    // is set, but its plain stream.mjpeg serves anyone. So when the socket is
    // refused we derive the image URL and show the camera anyway, no NVR config.
    test('is derived from a go2rtc ws endpoint', () {
      expect(
        go2rtcMjpegFallback('http://10.0.10.150:1984/api/ws?src=driveway'),
        'http://10.0.10.150:1984/api/stream.mjpeg?src=driveway',
      );
    });

    test('keeps the scheme and host', () {
      expect(
        go2rtcMjpegFallback('https://nvr.home:8555/api/ws?src=garage'),
        'https://nvr.home:8555/api/stream.mjpeg?src=garage',
      );
    });

    test('finds src even when it is not the first query param', () {
      expect(
        go2rtcMjpegFallback('http://h/api/ws?mode=webrtc&src=deck'),
        'http://h/api/stream.mjpeg?src=deck',
      );
    });

    test('declines a URL that is not a go2rtc ws endpoint', () {
      // No fallback to invent — a generic camera is not a go2rtc, and guessing a
      // stream.mjpeg path on it would 404.
      expect(go2rtcMjpegFallback('http://cam.local/live.mjpeg'), isNull);
      expect(go2rtcMjpegFallback('rtsp://cam/stream'), isNull);
      expect(go2rtcMjpegFallback('http://h/api/ws'), isNull); // no src
    });
  });

  group('cameraSrc cache-busting', () {
    test('a still is busted so a live camera never looks frozen', () {
      const url = 'http://go2rtc/api/frame.jpeg?src=gate';
      expect(cameraSrc(url, 'image_refresh', 0), endsWith('&_=0'));
      expect(cameraSrc(url, 'image_refresh', 7), endsWith('&_=7'));
      // A URL with no query gets a `?`, not a stray second `&`.
      expect(cameraSrc('http://cam/f.jpg', 'image_refresh', 2),
          'http://cam/f.jpg?_=2');
    });

    test('a stream is fetched once and left alone', () {
      const url = 'http://go2rtc/api/stream.mjpeg?src=gate';
      expect(cameraSrc(url, 'mjpeg', 5), url);
      expect(cameraSrc(url, 'go2rtc', 5), url);
    });
  });
}
