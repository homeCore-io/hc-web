import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/components/hc_now_playing.dart';
import '../../design/tokens.dart';

/// Media, as now-playing cards.
///
/// One card per *group*, not per speaker: two Sonos playing the same thing in
/// one room are one thing to a person, and rendering them as two cards with two
/// identical tracks is how you make a multi-room system look broken.
class MediaPage extends ConsumerWidget {
  const MediaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devicesAsync = ref.watch(devicesProvider);

    return Scaffold(
      body: devicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (devices) {
          final players = devices
              .where((d) => facetOf(d, d.schema) == DeviceFacet.mediaPlayer)
              .toList();

          if (players.isEmpty) {
            return Center(
              child: Text(
                'No media players.',
                style: TextStyle(color: t.surface.onBaseMuted),
              ),
            );
          }

          final groups = _groups(players);

          return ListView(
            padding: EdgeInsets.all(t.space.md),
            children: [
              Text(
                'Media',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: t.surface.onBase,
                ),
              ),
              SizedBox(height: t.space.md),
              for (final g in groups)
                Padding(
                  padding: EdgeInsets.only(bottom: t.space.md),
                  child: _Card(lead: g.first, group: g),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Buckets speakers by their group coordinator, leader first.
  ///
  /// A speaker that leads nothing still forms a group of one, so every player
  /// gets rendered exactly once.
  static List<List<DeviceState>> _groups(List<DeviceState> players) {
    final byCoordinator = <String, List<DeviceState>>{};
    for (final p in players) {
      byCoordinator.putIfAbsent(p.groupCoordinator ?? p.id, () => []).add(p);
    }

    final out = [
      for (final e in byCoordinator.entries)
        [...e.value]..sort((a, b) {
            // The coordinator leads the list — the card is written from its
            // point of view, and it is the one whose track is playing.
            final lead =
                (b.id == e.key ? 1 : 0).compareTo(a.id == e.key ? 1 : 0);
            return lead != 0 ? lead : a.displayName.compareTo(b.displayName);
          }),
    ];

    // Something playing outranks something idle.
    out.sort((a, b) {
      final playing = (b.first.playbackState == 'playing' ? 1 : 0)
          .compareTo(a.first.playbackState == 'playing' ? 1 : 0);
      return playing != 0
          ? playing
          : a.first.displayName.compareTo(b.first.displayName);
    });
    return out;
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.lead, required this.group});

  final DeviceState lead;
  final List<DeviceState> group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(devicesProvider.notifier);

    // Only offer what the plugin says it supports. hc-sonos declares 16 actions;
    // a plugin that declares none should not get a dead transport bar.
    bool can(String a) => lead.supportsAction(a);

    return HcNowPlaying(
      device: lead,
      group: group,
      onPlayPause: can('play')
          ? () => notifier.command(lead.id, {
                'action': lead.playbackState == 'playing' ? 'pause' : 'play',
              })
          : null,
      onNext: can('next')
          ? () => notifier.command(lead.id, {'action': 'next'})
          : null,
      onPrevious: can('previous')
          ? () => notifier.command(lead.id, {'action': 'previous'})
          : null,
      onVolume: can('set_volume')
          // Volume is per-speaker even inside a group — that is the whole reason
          // grouping is on the card.
          ? (id, v) => notifier.command(id, {
                'action': 'set_volume',
                'volume': v.round(),
              })
          : null,
      onSeek: can('seek')
          ? (secs) => notifier.command(lead.id, {
                'action': 'seek',
                'position_secs': secs.round(),
              })
          : null,
    );
  }
}
