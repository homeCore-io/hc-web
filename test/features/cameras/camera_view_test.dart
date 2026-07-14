import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/features/cameras/camera_source.dart';

/// The browser-free half of the camera view. The half that needs a browser — the
/// live decode inside an iframe or <img> — is verified by eye in a real browser.
void main() {
  group('transport selection', () {
    test('go2rtc and its transports route to the embedded player', () {
      for (final s in ['go2rtc', 'webrtc', 'mse', 'hls']) {
        expect(transportFor(s), CameraTransport.go2rtc, reason: s);
      }
    });

    test('a still is a still; everything else is a plain mjpeg image', () {
      expect(transportFor('image_refresh'), CameraTransport.imageRefresh);
      expect(transportFor('mjpeg'), CameraTransport.mjpeg);
      expect(transportFor('whatever'), CameraTransport.mjpeg);
    });
  });

  group('the go2rtc embed URL', () {
    // The whole point: iframe go2rtc's OWN stream.html so its WebSocket is
    // same-origin and WebRTC works with no api.origin config.
    test('a stream.html URL is used as-is', () {
      const u = 'http://10.0.10.150:1984/stream.html?src=driveway';
      expect(go2rtcEmbedUrl(u), u);
    });

    test('an api/ws endpoint is rewritten to the embed page', () {
      expect(
        go2rtcEmbedUrl('http://10.0.10.150:1984/api/ws?src=garage'),
        'http://10.0.10.150:1984/stream.html?src=garage',
      );
    });

    test('finds src even when it is not the first query param', () {
      expect(
        go2rtcEmbedUrl('http://h:1984/api/ws?mode=webrtc&src=deck'),
        'http://h:1984/stream.html?src=deck',
      );
    });

    test('a non-go2rtc URL is returned unchanged', () {
      expect(go2rtcEmbedUrl('http://cam.local/live'), 'http://cam.local/live');
    });
  });

  group('the MJPEG URL (for the plain-image path)', () {
    test('is derived from a go2rtc endpoint', () {
      expect(
        go2rtcMjpegUrl('http://10.0.10.150:1984/stream.html?src=driveway'),
        'http://10.0.10.150:1984/api/stream.mjpeg?src=driveway',
      );
    });

    test('declines a URL with no src', () {
      expect(go2rtcMjpegUrl('http://h:1984/stream.html'), isNull);
    });
  });

  group('cameraSrc cache-busting', () {
    test('a still is busted so a live camera never looks frozen', () {
      const url = 'http://go2rtc/api/frame.jpeg?src=gate';
      expect(cameraSrc(url, 'image_refresh', 0), endsWith('&_=0'));
      expect(cameraSrc('http://cam/f.jpg', 'image_refresh', 2),
          'http://cam/f.jpg?_=2');
    });

    test('a stream is fetched once and left alone', () {
      const url = 'http://go2rtc/api/stream.mjpeg?src=gate';
      expect(cameraSrc(url, 'mjpeg', 5), url);
    });
  });
}
