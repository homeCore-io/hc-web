import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/schema/attribute_policy.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/components/hc_tile.dart' show summarise;
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../devices/device_sheet.dart';
import 'home_edit_button.dart';

/// One device, as a row in a room card.
///
/// The tile grid blurred rooms together — a hundred equal-weight cards on a
/// black field. A room is instead a bordered container of these rows: an icon
/// and a name on the left, its control or reading on the right, hairlines
/// between. It scans like a list because it is one, which is the whole point.
class HomeEntityRow extends ConsumerStatefulWidget {
  const HomeEntityRow({super.key, required this.device});

  final DeviceState device;

  @override
  ConsumerState<HomeEntityRow> createState() => _HomeEntityRowState();
}

class _HomeEntityRowState extends ConsumerState<HomeEntityRow> {
  // Tapping the row opens the sheet already; the pencil is a visible hint that
  // it does, revealed on hover so a hundred rows are not each wearing one.
  bool _hover = false;

  DeviceState get device => widget.device;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final notifier = ref.read(devicesProvider.notifier);
    final facet = facetOf(device, device.schema);
    final offline = !device.available;
    final on = !offline && isOn(device);
    final alert = _alerting(device, offline);

    // A lock borrows neither the lamp's control nor the lamp's colour. `on` for
    // a lock means *unlocked*, so the default rule below would paint an open
    // exterior door in `accent.active` — the same amber as a light someone
    // deliberately left on. Unlocked is a state to notice, not a state to be
    // pleased about, so it gets `accent.danger` and locked stays quiet.
    final iconColour = offline
        ? t.accent.offline
        : alert
            ? t.accent.danger
            : facet == DeviceFacet.lock
                ? (on ? t.accent.danger : t.surface.onBaseMuted)
                : on
                    ? (lightColorOf(device) ?? t.accent.active)
                    : t.surface.onBaseMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: () => showDeviceSheet(context, device.id),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: t.space.md, vertical: t.space.sm + 1),
          child: Row(
            children: [
              Icon(HcIcons.forFacet(facet, on: on),
                  size: 19, color: iconColour),
              SizedBox(width: t.space.md),
              Expanded(
                child: Text(
                  device.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.bodyStyle.copyWith(
                      fontWeight: FontWeight.w500,
                      color:
                          offline ? t.surface.onBaseMuted : t.surface.onBase),
                ),
              ),
              if (_hover) HomeEditButton(deviceId: device.id),
              SizedBox(width: t.space.sm),
              _trailing(context, t, notifier, facet, offline, on, alert),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trailing(
    BuildContext context,
    HcTokens t,
    DevicesNotifier notifier,
    DeviceFacet facet,
    bool offline,
    bool on,
    bool alert,
  ) {
    if (offline) return _value('Offline', t.accent.offline, t);

    // A speaker: its state, and a play/pause if the plugin supports it.
    if (facet == DeviceFacet.mediaPlayer) {
      final playing = device.playbackState == 'playing';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _value(device.cleanTitle ?? (playing ? 'Playing' : 'Idle'),
              t.surface.onBaseMuted, t,
              max: 130),
          if (device.supportsAction('play')) ...[
            SizedBox(width: t.space.xs),
            _RoundIcon(
              icon: playing ? HcIcons.pause : HcIcons.play,
              onTap: () => notifier
                  .command(device.id, {'action': playing ? 'pause' : 'play'}),
            ),
          ],
        ],
      );
    }

    // A thermostat: current temperature, tap the row for the setpoint.
    if (facet == DeviceFacet.climate) {
      final cur = device.state['current_temperature'];
      final sp = device.state['setpoint'];
      final call = device.state['call_for'];
      final colour = call == 'cool'
          ? const Color(0xFF5AA9E6)
          : call == 'heat'
              ? t.accent.warn
              : t.surface.onBase;
      return _value(
        cur is num
            ? '${cur.toStringAsFixed(0)}°${sp is num ? ' → ${sp.toStringAsFixed(0)}°' : ''}'
            : '—',
        colour,
        t,
      );
    }

    // A fan: the named speed, then the toggle. Not "50%" — the device thinks in
    // steps, and "Medium" is what is printed on the wall control.
    if (facet == DeviceFacet.fan) {
      final speed = device.state['speed'];
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (on && speed is String && speed.isNotEmpty && speed != 'off')
            Padding(
              padding: EdgeInsets.only(right: t.space.sm),
              child: Text(fanSpeedLabel(speed),
                  style:
                      t.text.bodySmallStyle.copyWith(color: t.accent.active)),
            ),
          _Toggle(
            on: on,
            onChanged: () => notifier.command(device.id, {'on': !on}),
          ),
        ],
      );
    }

    // A lock is not a switch, and must not borrow one. See [_LockControl].
    if (facet == DeviceFacet.lock) {
      return _LockControl(device: device, notifier: notifier);
    }

    // Anything you switch, dim, open, lock: a toggle, with a level if it dims.
    if (facet.isActuator && facet != DeviceFacet.scene) {
      final level = levelOf(device);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (on && level != null && level < 0.99)
            Padding(
              padding: EdgeInsets.only(right: t.space.sm),
              child: Text('${(level * 100).round()}%',
                  style: t.text.bodySmallStyle.copyWith(
                      color: t.surface.onBaseMuted,
                      fontFeatures: t.numericFontFeatures)),
            ),
          _Toggle(
            on: on,
            onChanged: () => notifier.command(device.id, {'on': !on}),
          ),
        ],
      );
    }

    // A sensor: its reading, coloured when it is shouting.
    return _value(
      summarise(device),
      alert ? t.accent.danger : t.surface.onBase,
      t,
    );
  }

  Widget _value(String text, Color colour, HcTokens t, {double max = 160}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: max),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: t.text.bodyStyle.copyWith(
            fontWeight: FontWeight.w600,
            color: colour,
            fontFeatures: t.numericFontFeatures),
      ),
    );
  }

  static bool _alerting(DeviceState d, bool offline) {
    if (offline) return false;
    final s = d.state;
    if ((s['leak'] ?? s['water_detected']) == true) return true;
    if (s['smoke'] == true) return true;
    return false;
  }
}

/// A lock's state and its next move — never a switch.
///
/// A switch has a natural direction and a lock does not: nothing about a track
/// with a knob on it says which end is safe. Worse, the generic actuator branch
/// drives that switch from [isOn], which for a lock reports `!locked` — so the
/// bright, satisfied, "this is on" amber fired on **unlocked**, and the one row
/// on the page worth worrying about looked exactly like a lamp left on.
///
/// That branch also commanded `{'on': !on}`. Every lock plugin wants
/// `{'locked': bool}` (hc-yolink's `translate_command` errors with "cmd missing
/// boolean 'locked' field" on anything else), so the control was not merely
/// ambiguous, it was inert.
///
/// So: the state is a word, coloured by risk, and the button names the thing
/// that will happen rather than a control to be decoded. The loud filled button
/// is always the *safe* direction, and unlocking — the only action here that
/// matters to someone who merely has this tab open — asks first.
///
/// [DeviceFacet.lock] is reached whenever the device carries a `locked`
/// attribute, so this covers hc-isy and hc-zwave locks as well.
class _LockControl extends StatelessWidget {
  const _LockControl({required this.device, required this.notifier});

  final DeviceState device;
  final DevicesNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    // Deliberately nullable. A lock that reports neither — jammed, mid-cycle,
    // never polled — used to render as a confident "unlocked", because a
    // missing bool is not `true`.
    final locked =
        device.state['locked'] is bool ? device.state['locked'] as bool : null;

    final (String label, Color tone) = switch (locked) {
      true => ('Locked', t.surface.onBaseMuted),
      false => ('Unlocked', t.accent.danger),
      null => ('Unknown', t.surface.onBaseMuted),
    };

    // Locking is safe from anywhere, so it stays one tap and wears the filled
    // button. Unlocking is the one thing here worth stealing, so it is the
    // quiet outlined one and it confirms.
    final lockNext = locked != true;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Pill(label: label, tone: tone, filled: locked == false),
        SizedBox(width: t.space.sm),
        _LockButton(
          label: lockNext ? 'Lock' : 'Unlock',
          tone: locked == false ? t.accent.danger : t.surface.onBaseMuted,
          filled: locked == false,
          onTap: () => _command(context, lock: lockNext),
        ),
      ],
    );
  }

  Future<void> _command(BuildContext context, {required bool lock}) async {
    if (!lock && !await _confirmUnlock(context)) return;
    notifier.command(device.id, {'locked': lock});
  }

  Future<bool> _confirmUnlock(BuildContext context) async {
    final t = HcTokens.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => HcDialog(
        title: 'Unlock ${device.displayName}?',
        description: 'This physically unlocks the door. There is no undo, and '
            'nothing else will lock it again.',
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: t.accent.danger),
            child: const Text('Unlock'),
          ),
        ],
        child: const SizedBox.shrink(),
      ),
    );
    return ok ?? false;
  }
}

/// The state word, as a pill so it reads as a status and not as a button.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.tone, required this.filled});

  final String label;
  final Color tone;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? tone.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: t.radius.pillR,
        border: Border.all(
          color: filled ? tone.withValues(alpha: 0.45) : t.stroke.hairline,
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: t.text.overlineStyle.copyWith(
            fontWeight: FontWeight.w700, letterSpacing: 0.6, color: tone),
      ),
    );
  }
}

/// The next move, named. Filled means "this is the safe direction".
class _LockButton extends StatelessWidget {
  const _LockButton({
    required this.label,
    required this.tone,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final Color tone;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: t.space.sm + 2, vertical: 5),
        decoration: BoxDecoration(
          color: filled ? tone : Colors.transparent,
          borderRadius: t.radius.smR,
          border: Border.all(color: filled ? tone : t.stroke.hairline),
        ),
        child: Text(
          label,
          style: t.text.captionStyle.copyWith(
              fontWeight: FontWeight.w700,
              color: filled ? t.surface.base : tone),
        ),
      ),
    );
  }
}

/// The compact switch used at the right of a row.
class _Toggle extends StatelessWidget {
  const _Toggle({required this.on, required this.onChanged});

  final bool on;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    // 22, deliberately. It was briefly grown to 28 on a misread of "the toggle
    // is too small" — that was about the panel header, not this. A room card is
    // a dense list where the eye is scanning names; the control is found by its
    // fixed position at the right edge, not by its size, and a taller switch
    // here just spaces the rows apart for nothing.
    const h = 22.0;
    const w = h * 1.72;
    return Semantics(
      toggled: on,
      child: GestureDetector(
        onTap: onChanged,
        child: AnimatedContainer(
          duration: t.motion.d(t.motion.fast),
          curve: t.motion.curve,
          width: w,
          height: h,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: on ? t.accent.active : t.accent.inactive,
            borderRadius: t.radius.pillR,
          ),
          child: AnimatedAlign(
            duration: t.motion.d(t.motion.fast),
            curve: t.motion.emphasized,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: h - 6,
              height: h - 6,
              decoration: BoxDecoration(
                color: t.surface.raised,
                shape: BoxShape.circle,
                boxShadow: t.elevation.card,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small round icon button — the media play/pause on a row.
class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});

  final IconData icon;
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
        ),
        child: Icon(icon, size: 13, color: t.surface.onBase),
      ),
    );
  }
}
