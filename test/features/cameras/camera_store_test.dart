import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/features/cameras/camera_store.dart';

void main() {
  group('Camera showOnHome', () {
    test('defaults to shown', () {
      const cam = Camera(
        id: 'a',
        name: 'Driveway',
        url: 'http://x/stream',
        sourceType: 'webrtc',
      );
      expect(cam.showOnHome, isTrue);
    });

    test('absent config key means shown — old cameras keep appearing', () {
      final w = DashboardWidgetModel(
        id: 'a',
        type: 'camera_video',
        title: 'Driveway',
        refreshPolicy: DashboardRefreshPolicy.live,
        config: const {'url': 'http://x/stream', 'source_type': 'webrtc'},
      );
      expect(Camera.fromWidget(w)!.showOnHome, isTrue);
    });

    test('round-trips a hidden camera through the widget config', () {
      const cam = Camera(
        id: 'a',
        name: 'Attic',
        url: 'http://x/stream',
        sourceType: 'webrtc',
        showOnHome: false,
      );
      final w = cam.toWidget();
      expect(w.config['show_on_home'], isFalse);
      expect(Camera.fromWidget(w)!.showOnHome, isFalse);
    });

    test('shown cameras omit the key, keeping the wall document clean', () {
      const cam = Camera(
        id: 'a',
        name: 'Attic',
        url: 'http://x/stream',
        sourceType: 'webrtc',
      );
      expect(cam.toWidget().config.containsKey('show_on_home'), isFalse);
    });

    test('copyWith flips only showOnHome', () {
      const cam = Camera(
        id: 'a',
        name: 'Attic',
        url: 'http://x/stream',
        sourceType: 'webrtc',
        span: 2,
      );
      final hidden = cam.copyWith(showOnHome: false);
      expect(hidden.showOnHome, isFalse);
      expect(hidden.span, 2);
      expect(hidden.name, 'Attic');
    });
  });

  group('Camera homeLarge', () {
    test('defaults to compact single column', () {
      const cam = Camera(
        id: 'a',
        name: 'Driveway',
        url: 'http://x/stream',
        sourceType: 'webrtc',
      );
      expect(cam.homeLarge, isFalse);
    });

    test('round-trips a hero camera and omits the key when compact', () {
      const large = Camera(
        id: 'a',
        name: 'Driveway',
        url: 'http://x/stream',
        sourceType: 'webrtc',
        homeLarge: true,
      );
      final w = large.toWidget();
      expect(w.config['home_large'], isTrue);
      expect(Camera.fromWidget(w)!.homeLarge, isTrue);

      const small = Camera(
        id: 'a',
        name: 'Driveway',
        url: 'http://x/stream',
        sourceType: 'webrtc',
      );
      expect(small.toWidget().config.containsKey('home_large'), isFalse);
    });

    test('size and Home visibility are independent', () {
      const cam = Camera(
        id: 'a',
        name: 'Driveway',
        url: 'http://x/stream',
        sourceType: 'webrtc',
        showOnHome: false,
        homeLarge: true,
      );
      final w = cam.toWidget();
      final back = Camera.fromWidget(w)!;
      expect(back.showOnHome, isFalse);
      expect(back.homeLarge, isTrue);
    });
  });
}
