import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/design/components/hc_now_playing.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/camera_card.dart';

/// Shaped like a live Sonos: canonical media keys at the top level, grouping
/// alongside, and an art URL pointing at the speaker's own LAN address.
DeviceState _speaker(
  String id, {
  required String name,
  String state = 'paused',
  String? coordinator,
  List<String> members = const [],
  int volume = 40,
  String? title,
  int position = 0,
  int duration = 0,
}) =>
    DeviceState(
      id: id,
      name: name,
      pluginId: 'plugin.sonos',
      deviceType: 'media_player',
      available: true,
      state: {
        'state': state,
        'volume': volume,
        'group_coordinator': coordinator ?? id,
        'group_members': members.isEmpty ? [id] : members,
        'position_secs': position,
        'duration_secs': duration,
        if (title != null) 'title': title,
        'supported_actions': const [
          'play',
          'pause',
          'next',
          'previous',
          'set_volume',
          'seek',
        ],
      },
    );

Widget _host(Widget child) => MaterialApp(
      theme: hcTheme(HcSkin.ambientGlass),
      home: Scaffold(body: SizedBox(width: 640, height: 460, child: child)),
    );

void main() {
  group('now playing', () {
    testWidgets('shows the track and the room', (tester) async {
      await tester.pumpWidget(_host(HcNowPlaying(
        device: _speaker('sonos_office_1',
            name: 'Office-1',
            state: 'playing',
            title: 'The Rip Tide',
            position: 102,
            duration: 250),
      )));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('The Rip Tide'), findsOneWidget);
      expect(find.text('OFFICE-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows time remaining, not total', (tester) async {
      // What you want to know is how long is left.
      await tester.pumpWidget(_host(HcNowPlaying(
        device:
            _speaker('s', name: 'S', title: 'x', position: 102, duration: 250),
      )));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('1:42'), findsOneWidget);
      expect(find.text('−2:28'), findsOneWidget);
    });

    testWidgets('a stream with no duration says Live, not 0:00 / 0:00',
        (tester) async {
      // A radio stream has no end. A progress bar would be a lie about it.
      await tester.pumpWidget(_host(HcNowPlaying(
        device: _speaker('s',
            name: 'S', state: 'playing', title: 'ALT Radio', duration: 0),
      )));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Live'), findsOneWidget);
      expect(find.text('0:00'), findsNothing);
    });

    testWidgets('nothing playing is said plainly', (tester) async {
      await tester.pumpWidget(_host(HcNowPlaying(
        device: _speaker('s', name: 'S'),
      )));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Nothing playing'), findsOneWidget);
    });

    testWidgets('a group names its lead and gives each room its own volume',
        (tester) async {
      final lead = _speaker('sonos_office_1',
          name: 'Office-1',
          state: 'playing',
          title: 'x',
          coordinator: 'sonos_office_1',
          members: ['sonos_office_1', 'sonos_office_2'],
          volume: 40);
      final follower = _speaker('sonos_office_2',
          name: 'Office-2',
          coordinator: 'sonos_office_1',
          members: ['sonos_office_1', 'sonos_office_2'],
          volume: 28);

      await tester.pumpWidget(_host(
        HcNowPlaying(device: lead, group: [lead, follower]),
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('PLAYING IN 2 ROOMS'), findsOneWidget);
      // The coordinator is the speaker the others follow; removing it breaks the
      // group, so it is named rather than left for you to work out.
      expect(find.text('LEAD'), findsOneWidget);
      expect(find.text('Office-2'), findsOneWidget);
      expect(find.text('40'), findsOneWidget);
      expect(find.text('28'), findsOneWidget);
    });

    testWidgets('a lone speaker gets no empty group section', (tester) async {
      await tester.pumpWidget(_host(HcNowPlaying(
        device: _speaker('s', name: 'S', title: 'x'),
        group: [_speaker('s', name: 'S')],
      )));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('PLAYING IN'), findsNothing);
    });

    test('grouping accessors read what hc-sonos publishes', () {
      final s = _speaker('a', name: 'A', coordinator: 'b', members: ['a', 'b']);
      expect(s.groupCoordinator, 'b');
      expect(s.groupMembers, ['a', 'b']);
      expect(s.isGroupLead, isFalse);
      expect(_speaker('a', name: 'A').isGroupLead, isTrue);
    });
  });

  group('camera', () {
    testWidgets('a live stream is badged live', (tester) async {
      await tester.pumpWidget(_host(const SizedBox(
        width: 300,
        height: 170,
        child: CameraCard(
          name: 'Driveway',
          url: 'http://go2rtc.local/api/stream.mjpeg?src=driveway',
          sourceType: 'mjpeg',
        ),
      )));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Driveway'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('mjpeg'), findsOneWidget);
    });

    testWidgets('an unplayable source says so instead of showing black',
        (tester) async {
      // A black rectangle is indistinguishable from a quiet night — the one
      // thing a security wall must never be.
      await tester.pumpWidget(_host(const SizedBox(
        width: 300,
        height: 170,
        child: CameraCard(
          name: 'Deck',
          url: 'http://go2rtc.local/api/stream.m3u8?src=deck',
          sourceType: 'hls',
        ),
      )));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('needs a player'), findsOneWidget);
      expect(find.text('LIVE'), findsNothing);
    });

    test('image_refresh cache-busts, or the camera looks frozen', () {
      // Browsers cache stills aggressively. Without the buster the same frame is
      // served forever and a live camera looks frozen — the worst failure a
      // security wall can have.
      const url = 'http://go2rtc.local/api/frame.jpeg?src=gate';
      expect(cameraSrc(url, 'image_refresh', 0), endsWith('&_=0'));
      expect(cameraSrc(url, 'image_refresh', 1), endsWith('&_=1'));

      // A URL with no existing query gets a `?`, not a second `&`.
      expect(cameraSrc('http://cam/frame.jpg', 'image_refresh', 2),
          'http://cam/frame.jpg?_=2');

      // A stream is fetched once and left alone.
      expect(cameraSrc(url, 'mjpeg', 5), url);
      expect(cameraSrc(url, 'webrtc', 5), url);
    });

    test('only the sources we can actually play are rendered', () {
      expect(cameraRenderable('mjpeg'), isTrue);
      expect(cameraRenderable('image_refresh'), isTrue);
      // These need a real player; claiming to render them would show black.
      expect(cameraRenderable('hls'), isFalse);
      expect(cameraRenderable('webrtc'), isFalse);
    });
  });
}
