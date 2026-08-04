import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/models/plugin_entry.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/plugins_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/components/hc_now_playing.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_group.dart';
import '../../shared/widgets/section_scaffold.dart';

/// Media, as now-playing cards.
///
/// One card per *group*, not per speaker: two Sonos playing the same thing in
/// one room are one thing to a person, and rendering them as two cards with two
/// identical tracks is how you make a multi-room system look broken.
class MediaPage extends ConsumerWidget {
  const MediaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesProvider);
    final plugins = ref.watch(pluginsProvider).value;

    // Header stats are per *group* — the same unit the cards render — so "2
    // playing" matches two cards, not four speakers.
    final players = (devicesAsync.value ?? const <DeviceState>[])
        .where((d) => facetOf(d, d.schema) == DeviceFacet.mediaPlayer)
        .toList();
    final groups = _groups(players);
    final playing =
        groups.where((g) => g.first.playbackState == 'playing').length;
    final idle = groups.length - playing;

    return SectionScaffold(
      title: 'Media',
      stats: devicesAsync.hasValue && groups.isNotEmpty
          ? [
              if (playing > 0)
                SectionStat(
                    value: '$playing',
                    label: 'playing',
                    tone: SectionTone.active,
                    glow: true),
              SectionStat(value: '$idle', label: 'idle'),
            ]
          : const [],
      // Built under a Builder so tokens resolve in the Midnight theme the
      // scaffold applies, not the shell's own skin.
      child: Builder(builder: (context) {
        final t = HcTokens.of(context);
        return devicesAsync.when(
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

            // Same room-then-source grouping as Scenes: a player's room is its
            // area; players with no room fall into a group named for their
            // source (Sonos, etc.).
            final sections = _sections(_groups(players), plugins);

            return ListView(
              padding: EdgeInsets.fromLTRB(
                  t.space.md, t.space.sm, t.space.md, t.space.xl),
              children: [
                for (final s in sections)
                  SectionGroup(
                    id: 'media:${s.key}',
                    title: s.title,
                    tag: s.isRoom ? null : 'Source',
                    tagAccent: true,
                    count: s.count,
                    child: Column(
                      children: [
                        for (final g in s.groups)
                          Padding(
                            padding: EdgeInsets.only(bottom: t.space.sm),
                            child: _Card(lead: g.first, group: g),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      }),
    );
  }

  /// Buckets coordinator-groups by room, then by source for the room-less.
  /// Rooms A→Z first, then source groups A→Z.
  static List<_MediaSection> _sections(
      List<List<DeviceState>> groups, List<PluginEntry>? plugins) {
    final rooms = <String, List<List<DeviceState>>>{};
    final sources = <String, List<List<DeviceState>>>{};
    for (final g in groups) {
      final area = (g.first.effectiveArea?.isNotEmpty ?? false)
          ? g.first.effectiveArea!
          : null;
      if (area != null) {
        rooms.putIfAbsent(area, () => []).add(g);
      } else {
        sources.putIfAbsent(g.first.pluginId, () => []).add(g);
      }
    }

    String sourceName(String id) {
      final match = plugins?.where((p) => p.pluginId == id);
      return (match != null && match.isNotEmpty)
          ? match.first.displayName
          : humanize(id.replaceFirst('plugin.', ''));
    }

    final out = <_MediaSection>[];
    final roomKeys = rooms.keys.toList()
      ..sort((a, b) =>
          humanize(a).toLowerCase().compareTo(humanize(b).toLowerCase()));
    for (final k in roomKeys) {
      out.add(_MediaSection(
          key: k, title: humanize(k), isRoom: true, groups: rooms[k]!));
    }
    final srcKeys = sources.keys.toList()
      ..sort((a, b) =>
          sourceName(a).toLowerCase().compareTo(sourceName(b).toLowerCase()));
    for (final k in srcKeys) {
      out.add(_MediaSection(
          key: 'src_$k',
          title: sourceName(k),
          isRoom: false,
          groups: sources[k]!));
    }
    return out;
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

/// A room (or source) worth of media groups, for one [SectionGroup].
class _MediaSection {
  _MediaSection({
    required this.key,
    required this.title,
    required this.isRoom,
    required this.groups,
  });

  final String key;
  final String title;
  final bool isRoom;
  final List<List<DeviceState>> groups;

  int get _playing =>
      groups.where((g) => g.first.playbackState == 'playing').length;

  String get count => '$_playing of ${groups.length} playing';
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
