import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/models/device_state.dart';
import '../hc_icons.dart';
import '../tokens.dart';

/// A media player, as a now-playing card.
///
/// The card takes its colour **from the record**: the artwork is blurred and
/// bloomed behind it, so a warm album makes a warm card. It is the one place the
/// palette is allowed to be hijacked — everywhere else the amber accent is the
/// only bold thing, and that restraint is what makes this land.
///
/// Artwork comes through core's proxy (`/devices/:id/media/art`), never from the
/// speaker directly: hc-sonos publishes an absolute LAN URL
/// (`http://10.0.10.28:1400/getaa?...`) which a browser can only load while on
/// the same subnet, and which an HTTPS page blocks outright as mixed content.
///
/// Multi-room is on the card rather than in a menu, because grouping *is* the
/// Sonos story: which rooms are playing, which one leads, each with its own
/// volume.
class HcNowPlaying extends StatelessWidget {
  const HcNowPlaying({
    super.key,
    required this.device,
    this.group = const [],
    this.onPlayPause,
    this.onNext,
    this.onPrevious,
    this.onVolume,
    this.onSeek,
  });

  final DeviceState device;

  /// The other speakers in this group, if any. The card only renders the group
  /// when there is one — a single speaker gets no empty section.
  final List<DeviceState> group;

  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;

  /// (deviceId, 0–100) — per-speaker volume, because that is how a group works.
  final void Function(String deviceId, double volume)? onVolume;
  final ValueChanged<double>? onSeek;

  bool get _playing => device.playbackState == 'playing';

  /// Core proxies the artwork so a browser can actually load it.
  String get _artUrl => '/api/v1/devices/${device.id}/media/art';

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    // Use the sanitized title so a station reporting a raw `hls.m3u8?…` stream
    // URL as its "track" collapses to the idle row instead of rendering a card
    // full of query-string junk.
    final title = device.cleanTitle;
    // Never invented: when the stream gives no name, the card says what is
    // true — it is playing — and the artwork and transport carry the rest.
    final headline = (title == null || title.isEmpty) ? 'Playing' : title;

    // An idle speaker collapses to a row.
    //
    // It used to get the full treatment regardless — a 128px cover well, a
    // progress bar, a transport deck — so five silent Sonos filled the page with
    // ~290px each of mostly nothing, and the one that WAS playing had no more
    // presence than the four that weren't. A card should be as big as it has
    // something to say.
    // Artwork counts as "something to show". A radio stream frequently reports
    // cover art and no title whatsoever, and collapsing that to the idle row
    // told the user a playing speaker was silent.
    if ((title == null || title.isEmpty) && !device.hasArtwork) {
      return _IdleSpeaker(
        device: device,
        group: group,
        onPlayPause: onPlayPause,
        onVolume: onVolume,
      );
    }

    return ClipRRect(
      borderRadius: t.radius.lgR,
      child: Stack(
        children: [
          // The bloom. It is the artwork, scaled up and blurred to nothing but
          // its colour — so the card is *of* the record, not merely next to it.
          Positioned.fill(
            child: _ArtBloom(url: _artUrl, key: ValueKey(_artUrl)),
          ),
          // Without this scrim the text would be illegible over a bright cover.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    t.surface.base.withValues(alpha: 0.55),
                    t.surface.base.withValues(alpha: 0.88),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(t.space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Cover(url: _artUrl),
                    SizedBox(width: t.space.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(HcIcons.forFacetMedia,
                                  size: 13, color: t.surface.onBaseMuted),
                              SizedBox(width: t.space.xs + 1),
                              Text(
                                device.displayName.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.4,
                                  color: t.surface.onBaseMuted,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: t.space.sm),
                          Text(
                            // Non-null past the idle early-return above.
                            headline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 24,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                              color: t.surface.onBase,
                            ),
                          ),
                          if (device.artist case final a?
                              when a.isNotEmpty) ...[
                            SizedBox(height: t.space.xs),
                            Text(
                              a,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                color: t.surface.onBaseMuted,
                              ),
                            ),
                          ],
                          if (device.album case final a? when a.isNotEmpty)
                            Text(
                              a,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: t.surface.onBaseMuted
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: t.space.lg),
                _Seek(device: device, onSeek: onSeek),
                SizedBox(height: t.space.md),
                _Transport(
                  playing: _playing,
                  onPlayPause: onPlayPause,
                  onNext: onNext,
                  onPrevious: onPrevious,
                  volume: device.volumePercent?.toDouble(),
                  onVolume:
                      onVolume == null ? null : (v) => onVolume!(device.id, v),
                ),
                if (group.length > 1) ...[
                  SizedBox(height: t.space.md),
                  Divider(color: t.stroke.hairline, height: 1),
                  SizedBox(height: t.space.md),
                  _Group(
                    members: group,
                    coordinator: device.groupCoordinator,
                    onVolume: onVolume,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The artwork, blurred until it is only colour.
class _ArtBloom extends StatelessWidget {
  const _ArtBloom({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Image.network(
      url,
      fit: BoxFit.cover,
      // No artwork is normal — a radio stream, a paused speaker. Fall back to the
      // ordinary surface rather than showing a broken image.
      errorBuilder: (_, __, ___) => ColoredBox(color: t.surface.raised),
      frameBuilder: (context, child, frame, wasSync) => AnimatedOpacity(
        opacity: frame == null ? 0 : 1,
        duration: t.motion.d(t.motion.slow),
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 46, sigmaY: 46),
          child: Transform.scale(scale: 1.6, child: child),
        ),
      ),
    );
  }
}

/// A speaker with nothing to say, said briefly.
class _IdleSpeaker extends StatelessWidget {
  const _IdleSpeaker({
    required this.device,
    required this.group,
    this.onPlayPause,
    this.onVolume,
  });

  final DeviceState device;
  final List<DeviceState> group;
  final VoidCallback? onPlayPause;
  final void Function(String id, double volume)? onVolume;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final rooms = group.length > 1 ? ' · ${group.length} rooms' : '';

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: t.space.md, vertical: t.space.sm + 2),
      decoration: BoxDecoration(
        color: t.surface.raised,
        borderRadius: t.radius.mdR,
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Row(
        children: [
          Icon(HcIcons.forFacetMedia, size: 16, color: t.surface.onBaseMuted),
          SizedBox(width: t.space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${device.displayName}$rooms',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: t.surface.onBase,
                  ),
                ),
                Text(
                  device.available ? 'Nothing playing' : 'Offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: t.surface.onBaseMuted,
                  ),
                ),
              ],
            ),
          ),
          if (onPlayPause != null && device.available)
            IconButton(
              icon: const Icon(HcIcons.play, size: 15),
              tooltip: 'Play',
              color: t.surface.onBaseMuted,
              onPressed: onPlayPause,
            ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Container(
      width: 128,
      height: 128,
      decoration: BoxDecoration(
        borderRadius: t.radius.mdR,
        color: t.surface.sunken,
        boxShadow: const [
          BoxShadow(
            color: Color(0xB3000000),
            blurRadius: 40,
            offset: Offset(0, 18),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(
            HcIcons.forFacetMedia,
            size: 34,
            color: t.surface.onBaseMuted,
          ),
        ),
      ),
    );
  }
}

class _Seek extends StatelessWidget {
  const _Seek({required this.device, required this.onSeek});

  final DeviceState device;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final pos = device.positionSecs ?? 0;
    final dur = device.durationSecs ?? 0;

    // A live radio stream has no duration. Showing a 0:00 / 0:00 bar would be a
    // lie about a thing that has no end.
    if (dur <= 0) {
      return Text(
        device.playbackState == 'playing' ? 'Live' : '—',
        style: TextStyle(
          fontSize: 11,
          color: t.surface.onBaseMuted,
          fontFeatures: t.numericFontFeatures,
        ),
      );
    }

    final frac = (pos / dur).clamp(0.0, 1.0);

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: onSeek == null
                ? null
                : (d) => onSeek!(
                    (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0) * dur),
            child: SizedBox(
              height: 12,
              child: Center(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.surface.onBase.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(t.radius.pill),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: frac,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: t.surface.onBase,
                        borderRadius: BorderRadius.circular(t.radius.pill),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: t.space.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_mmss(pos), style: _timeStyle(t)),
            // Remaining, not total: what you want to know is how long is left.
            Text('−${_mmss(dur - pos)}', style: _timeStyle(t)),
          ],
        ),
      ],
    );
  }

  TextStyle _timeStyle(HcTokens t) => TextStyle(
        fontSize: 11,
        color: t.surface.onBaseMuted,
        fontFeatures: t.numericFontFeatures,
      );

  static String _mmss(int secs) {
    final s = secs.clamp(0, 86400);
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.playing,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.volume,
    required this.onVolume,
  });

  final bool playing;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final double? volume;
  final ValueChanged<double>? onVolume;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Row(
      children: [
        _Button(icon: HcIcons.previous, onTap: onPrevious),
        SizedBox(width: t.space.sm),
        _Button(
          icon: playing ? HcIcons.pause : HcIcons.play,
          onTap: onPlayPause,
          primary: true,
        ),
        SizedBox(width: t.space.sm),
        _Button(icon: HcIcons.next, onTap: onNext),
        const Spacer(),
        if (volume != null && onVolume != null)
          SizedBox(
            width: 150,
            child: Row(
              children: [
                Icon(HcIcons.volume, size: 15, color: t.surface.onBaseMuted),
                SizedBox(width: t.space.sm),
                Expanded(
                  child: _Bar(
                    value: volume! / 100,
                    colour: t.surface.onBaseMuted,
                    onChanged: (v) => onVolume!(v * 100),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Button extends StatelessWidget {
  const _Button(
      {required this.icon, required this.onTap, this.primary = false});

  final IconData icon;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final size = primary ? 46.0 : 36.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: primary ? t.surface.onBase : Colors.transparent,
          border: primary ? null : Border.all(color: t.stroke.hairline),
        ),
        child: Icon(
          icon,
          size: primary ? 19 : 15,
          color: primary ? t.surface.base : t.surface.onBaseMuted,
        ),
      ),
    );
  }
}

/// Multi-room. Which rooms are playing, which leads, each with its own volume —
/// on the card, because grouping is the whole point of a Sonos.
class _Group extends StatelessWidget {
  const _Group({
    required this.members,
    required this.coordinator,
    required this.onVolume,
  });

  final List<DeviceState> members;
  final String? coordinator;
  final void Function(String deviceId, double volume)? onVolume;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PLAYING IN ${members.length} ROOMS',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
            color: t.surface.onBaseMuted,
          ),
        ),
        SizedBox(height: t.space.sm),
        for (final m in members)
          Padding(
            padding: EdgeInsets.symmetric(vertical: t.space.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 130,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          m.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: t.surface.onBase,
                          ),
                        ),
                      ),
                      // The coordinator is the speaker the others follow; the
                      // group breaks if you remove it, so it is named.
                      if (m.id == coordinator) ...[
                        SizedBox(width: t.space.xs + 1),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: t.accent.success.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'LEAD',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: t.accent.success,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: t.space.md),
                Expanded(
                  child: _Bar(
                    value: (m.volumePercent ?? 0) / 100,
                    colour: t.accent.success,
                    onChanged: onVolume == null
                        ? null
                        : (v) => onVolume!(m.id, v * 100),
                  ),
                ),
                SizedBox(width: t.space.sm),
                SizedBox(
                  width: 26,
                  child: Text(
                    '${m.volumePercent ?? 0}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      color: t.surface.onBaseMuted,
                      fontFeatures: t.numericFontFeatures,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A draggable bar with no thumb — the fill *is* the value.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.value,
    required this.colour,
    required this.onChanged,
  });

  final double value;
  final Color colour;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return LayoutBuilder(
      builder: (context, box) {
        void set(Offset p) =>
            onChanged?.call((p.dx / box.maxWidth).clamp(0.0, 1.0));

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => set(d.localPosition),
          onHorizontalDragUpdate: (d) => set(d.localPosition),
          child: SizedBox(
            height: 12,
            child: Center(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: t.surface.onBase.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(t.radius.pill),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value.clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colour,
                      borderRadius: BorderRadius.circular(t.radius.pill),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
