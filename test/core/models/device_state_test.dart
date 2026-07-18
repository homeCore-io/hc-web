import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';

void main() {
  group('DeviceState.fromJson', () {
    test('parses full record', () {
      final d = DeviceState.fromJson({
        'device_id': 'light_living',
        'canonical_name': 'living_room.floor_lamp',
        'plugin_id': 'plugin.hue',
        'name': 'Living Room',
        'area': 'living_room',
        'available': true,
        'attributes': {'on': true, 'brightness': 128},
      });

      expect(d.id, 'light_living');
      expect(d.canonicalName, 'living_room.floor_lamp');
      expect(d.ruleReference, 'living_room.floor_lamp');
      expect(d.pluginId, 'plugin.hue');
      expect(d.name, 'Living Room');
      expect(d.area, 'living_room');
      expect(d.available, isTrue);
      expect(d.state['on'], isTrue);
      expect(d.state['brightness'], 128);
    });

    test('handles missing optional fields', () {
      final d = DeviceState.fromJson({
        'device_id': 'sensor_1',
        'plugin_id': 'plugin.zwave',
        'available': false,
        'attributes': {},
      });

      expect(d.id, 'sensor_1');
      expect(d.name, isNull);
      expect(d.area, isNull);
      expect(d.available, isFalse);
      expect(d.state, isEmpty);
    });

    test('handles missing plugin_id', () {
      final d = DeviceState.fromJson({
        'device_id': 'timer_kitchen',
        'available': true,
        'attributes': {'status': 'idle'},
      });

      expect(d.pluginId, '');
    });

    test('handles null attributes gracefully', () {
      final d = DeviceState.fromJson({
        'device_id': 'x',
        'plugin_id': 'p',
        'available': true,
        'attributes': null,
      });

      expect(d.state, isEmpty);
    });

    test('displayName falls back to id when name is null', () {
      final d = DeviceState.fromJson({
        'device_id': 'switch_garden',
        'plugin_id': 'core.switch',
        'available': true,
        'attributes': {},
      });

      expect(d.displayName, 'switch_garden');
      expect(d.ruleReference, 'switch_garden');
    });

    test('displayName uses name when set', () {
      final d = DeviceState.fromJson({
        'device_id': 'switch_garden',
        'plugin_id': 'core.switch',
        'name': 'Garden Switch',
        'available': true,
        'attributes': {},
      });

      expect(d.displayName, 'Garden Switch');
    });

    test('parses generic media player contract', () {
      final d = DeviceState.fromJson({
        'device_id': 'sonos_living',
        'plugin_id': 'plugin.sonos',
        'device_type': 'media_player',
        'available': true,
        'attributes': {
          'state': 'playing',
          'title': 'Blue Train',
          'artist': 'John Coltrane',
          'album': 'Blue Train',
          'position_secs': 35,
          'duration_secs': 610,
          'volume': 27,
          'muted': false,
          'supported_actions': ['play', 'pause', 'stop', 'set_volume'],
          'ui_enrichments': ['favorites', 'grouping'],
        },
      });

      expect(d.isMediaPlayer, isTrue);
      expect(d.playbackState, 'playing');
      expect(d.title, 'Blue Train');
      expect(d.artist, 'John Coltrane');
      expect(d.album, 'Blue Train');
      expect(d.positionSecs, 35);
      expect(d.durationSecs, 610);
      expect(d.volumePercent, 27);
      expect(d.muted, isFalse);
      expect(d.supportedActions, contains('stop'));
      expect(d.uiEnrichments, contains('favorites'));
      expect(d.supportsAction('set_volume'), isTrue);
      expect(d.supportsAction('next'), isFalse);
    });

    test('reads legacy media keys and sonos enrichments', () {
      final d = DeviceState.fromJson({
        'device_id': 'sonos_kitchen',
        'plugin_id': 'plugin.sonos',
        'device_type': 'media_player',
        'available': true,
        'attributes': {
          'media_title': 'News Hour',
          'media_artist': 'BBC',
          'media_album': 'Live',
          'media_position': 5,
          'media_duration': 1800,
          'sonos': {
            'favorites': ['News', 'Jazz'],
            'group_members': ['sonos_kitchen'],
          },
        },
      });

      expect(d.title, 'News Hour');
      expect(d.artist, 'BBC');
      expect(d.album, 'Live');
      expect(d.positionSecs, 5);
      expect(d.durationSecs, 1800);
      expect(d.sonos['favorites'], ['News', 'Jazz']);
      expect(d.supportsAction('play'), isTrue);
    });
  });

  group('cleanTitle / mediaSubtitle — never surface a stream URL', () {
    DeviceState media(String? title, {String state = 'paused'}) =>
        DeviceState.fromJson({
          'device_id': 'sonos',
          'plugin_id': 'plugin.sonos',
          'device_type': 'media_player',
          'available': true,
          'attributes': {
            'state': state,
            if (title != null) 'title': title,
          },
        });

    test('a real track title comes through clean', () {
      expect(media('Blue Train').cleanTitle, 'Blue Train');
      expect(media('Blue Train').mediaSubtitle, 'Blue Train');
    });

    test('a raw hls stream URL is suppressed', () {
      final url = 'hls.m3u8?rj-ttl=5&rj-tok=AAABn3HDYNcAMqHoG3c7jmCp4Q';
      expect(media(url).cleanTitle, isNull);
      // Falls back to the human playback state instead of the URL junk.
      expect(media(url).mediaSubtitle, 'paused');
    });

    test('a query-string blob title is suppressed', () {
      final blob = 'a24943?fbbroadcast=0&devicename=sonos&clientType=sonos';
      expect(media(blob).cleanTitle, isNull);
    });

    test('no title at all leaves cleanTitle null', () {
      expect(media(null).cleanTitle, isNull);
      expect(media(null).mediaSubtitle, 'paused');
    });
  });
}
