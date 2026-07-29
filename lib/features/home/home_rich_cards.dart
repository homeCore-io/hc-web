import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/components/hc_now_playing.dart';
import '../../design/components/hc_surface.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../devices/device_sheet.dart';
import 'home_edit_button.dart';

/// The domain-rich cards the house shows for the two device kinds an on/off tile
/// cannot do justice: a speaker and a thermostat. Both are wired straight to the
/// devices notifier — they command directly rather than routing every transport
/// tap back up through the page.

/// A media player, as a now-playing card, on the house.
///
/// Reuses [HcNowPlaying] — the same card the Media page shows — so a Sonos looks
/// and behaves identically wherever you meet it. Idle, it collapses to a slim
/// row; playing, it blooms into the artwork. Multi-room control stays on the
/// Media page; here the group section is omitted to keep the house calm.
class HomeMediaCard extends ConsumerWidget {
  const HomeMediaCard({super.key, required this.device});

  final DeviceState device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final notifier = ref.read(devicesProvider.notifier);
    bool can(String a) => device.supportsAction(a);

    // The whole card opens the device, like every other thing in a room does.
    // Without this a playing speaker was the one device on the house you could
    // not get a panel for.
    //
    // A GestureDetector wrapping the Stack rather than a layer inside it: the
    // transport buttons are descendants, so they win the gesture arena for
    // their own taps, and the card only claims the ones nothing else wanted.
    // An InkWell underneath the card would never be reached at all.
    return GestureDetector(
      onTap: () => showDeviceSheet(context, device.id),
      child: Stack(
        children: [
          HcNowPlaying(
            device: device,
            onPlayPause: can('play')
                ? () => notifier.command(device.id, {
                      'action':
                          device.playbackState == 'playing' ? 'pause' : 'play',
                    })
                : null,
            onNext: can('next')
                ? () => notifier.command(device.id, {'action': 'next'})
                : null,
            onPrevious: can('previous')
                ? () => notifier.command(device.id, {'action': 'previous'})
                : null,
            onVolume: can('set_volume')
                ? (id, v) => notifier
                    .command(id, {'action': 'set_volume', 'volume': v.round()})
                : null,
            onSeek: can('seek')
                ? (secs) => notifier.command(device.id,
                    {'action': 'seek', 'position_secs': secs.round()})
                : null,
          ),
          // A backed pencil, so it reads over both the bright bloom of a playing
          // card and the flat surface of an idle one.
          Positioned(
            top: t.space.xs,
            right: t.space.xs,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.surface.base.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: HomeEditButton(deviceId: device.id),
            ),
          ),
        ],
      ),
    );
  }
}

/// A thermostat, as a climate card.
///
/// Current temperature is the headline; the setpoint is adjustable in place
/// (±0.5, the step the plugin honours — `{"command":"set_setpoint",...}`), and
/// the card says out loud whether it is actively heating or cooling, which a
/// bare number never does.
class HomeClimateCard extends ConsumerWidget {
  const HomeClimateCard({super.key, required this.device, this.onTap});

  final DeviceState device;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final s = device.state;
    final notifier = ref.read(devicesProvider.notifier);

    final current = (s['current_temperature'] as num?)?.toDouble();
    final setpoint = (s['setpoint'] as num?)?.toDouble();
    final mode = (s['mode'] as String?) ?? '';
    final callFor = (s['call_for'] as String?) ?? 'idle';
    final active = callFor == 'cool' || callFor == 'heat';
    final accent = switch (callFor) {
      'cool' => const Color(0xFF5AA9E6),
      'heat' => t.accent.warn,
      _ => t.surface.onBaseMuted,
    };

    void bump(double by) {
      if (setpoint == null) return;
      notifier.command(
          device.id, {'command': 'set_setpoint', 'value': (setpoint + by)});
    }

    String temp(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}°';

    return HcSurface(
      onTap: onTap,
      glowColor: accent,
      glowIntensity: active ? 0.5 : 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(HcIcons.forFacet(DeviceFacet.climate),
                  size: 15, color: accent),
              SizedBox(width: t.space.sm),
              Expanded(
                child: Text(
                  device.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.surface.onBase,
                  ),
                ),
              ),
              _Pill(
                label:
                    active ? '${callFor}ing'.toUpperCase() : mode.toUpperCase(),
                colour: accent,
                filled: active,
              ),
            ],
          ),
          SizedBox(height: t.space.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                temp(current),
                style: TextStyle(
                  fontSize: 30,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                  color: t.surface.onBase,
                  fontFeatures: t.numericFontFeatures,
                ),
              ),
              const Spacer(),
              if (setpoint != null) ...[
                _Step(glyph: '−', onTap: () => bump(-0.5)),
                SizedBox(width: t.space.sm),
                Column(
                  children: [
                    Text('TARGET',
                        style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: t.surface.onBaseMuted)),
                    Text(temp(setpoint),
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: accent,
                            fontFeatures: t.numericFontFeatures)),
                  ],
                ),
                SizedBox(width: t.space.sm),
                _Step(glyph: '+', onTap: () => bump(0.5)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.glyph, required this.onTap});

  final String glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: t.stroke.hairline),
          color: t.surface.sunken,
        ),
        child: Text(
          glyph,
          style: TextStyle(
            fontSize: 18,
            height: 1,
            fontWeight: FontWeight.w500,
            color: t.surface.onBase,
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(
      {required this.label, required this.colour, required this.filled});

  final String label;
  final Color colour;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? colour.withValues(alpha: 0.18) : t.surface.sunken,
        borderRadius: BorderRadius.circular(t.radius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: filled ? colour : t.surface.onBaseMuted,
        ),
      ),
    );
  }
}
