import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';

DeviceState _d(String id, Map<String, dynamic> state) => DeviceState(
      id: id,
      name: id,
      pluginId: 'plugin.test',
      deviceType: 'media_player',
      available: true,
      state: state,
    );

/// The rule the room card uses to decide whether a media device blooms into a
/// now-playing card or stays a row. Mirrors `_Room` in home_page.dart.
bool blooms(DeviceState d) =>
    d.playbackState == 'playing' &&
    ((d.cleanTitle ?? '').isNotEmpty || d.hasArtwork);

void main() {
  group('a media device blooms only when it has something to show', () {
    test('a Sonos playing a station blooms', () {
      expect(
        blooms(_d('sonos', {
          'state': 'playing',
          'media_title': 'AlternativeRadio.us',
        })),
        isTrue,
      );
    });

    test('an idle speaker stays a row', () {
      expect(blooms(_d('sonos', {'state': 'paused'})), isFalse);
    });

    test('a Roku TV on an HDMI input stays a row', () {
      // The bug this locks. hc-roku reports `playing` for an input and for the
      // tuner, because neither goes through `query/media-player` — so the old
      // `playbackState == 'playing'` rule bloomed Office TV into a card with no
      // title, no artwork and, since the card carried no tap target, no way to
      // open the device at all.
      expect(
        blooms(_d('roku_yk00xf435811', {
          'state': 'playing',
          'source': 'HDMI 1',
          'app_name': 'HDMI 1',
        })),
        isFalse,
      );
    });

    test('a Roku in an app that reports a title does bloom', () {
      expect(
        blooms(_d('roku', {
          'state': 'playing',
          'app_name': 'Netflix',
          'media_title': 'The Diplomat',
        })),
        isTrue,
      );
    });

    test('a titleless radio stream still blooms — it has artwork', () {
      // Reported by John and reproduced on Office-1: an iHeart station plays
      // with `media_image_url` set and NO title of any kind. Judged on title
      // alone the speaker looked idle while it was audibly playing.
      expect(
        blooms(_d('sonos_office_1', {
          'state': 'playing',
          'media_image_url':
              'http://10.0.10.40:1400/getaa?s=1&u=x-sonosapi-stream%3a…',
        })),
        isTrue,
      );
    });

    test('artwork alone does not bloom a paused speaker', () {
      expect(
        blooms(_d('sonos', {
          'state': 'paused',
          'media_image_url': 'http://10.0.10.40:1400/getaa?s=1',
        })),
        isFalse,
      );
    });

    test('a Roku on HDMI has neither title nor artwork, so still no bloom', () {
      expect(
        blooms(_d('roku', {
          'state': 'playing',
          'source': 'HDMI 1',
          'app_name': 'HDMI 1',
        })),
        isFalse,
      );
    });

    test('a junk stream URL as a title does not count', () {
      // `cleanTitle` already drops these; the rule inherits that for free
      // rather than re-deciding what a title is.
      expect(
        blooms(_d('sonos', {
          'state': 'playing',
          'media_title': 'https://example.com/hls.m3u8?token=abc',
        })),
        isFalse,
      );
    });
  });
}
