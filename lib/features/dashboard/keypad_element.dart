import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/card_style.dart';
import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/tokens.dart';

/// A keypad you draw, with its real buttons on it.
///
/// **A keypad is not a fact about a room; it is a set of buttons.** John, on
/// seeing one listed with a dash beside it: *"Lutron keypad the hallway 6
/// button absolutely can be pressed on the main repeater and should be a
/// controlled device."* RadioRA 2 accepts a virtual press on every button of
/// every keypad, Pico and VCRX in the house — so a page that reported one
/// existed was describing a control instead of offering it.
///
/// **The promise here is `available_buttons`, not a writable attribute.** The
/// switch's rule does not apply, because pressing is not an attribute write:
/// `hc-lutron` takes `{"press_button": 3}` as a command, the way a scene takes
/// an activation. What stands in for the promise is the device's own list — a
/// keypad publishes every button a person can press, LED or not, and a button
/// that is not on that list is one this plugin will not send.
///
/// **The LEDs are the state.** A Lutron keypad's LED is what tells you the
/// scene it triggers is currently on, and it is the only state a keypad has.
/// Drawing the buttons without them would be drawing a remote control that
/// cannot tell you anything.
class KeypadElement extends ConsumerWidget {
  const KeypadElement({super.key, required this.config});

  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value;

    final id = (config['device_id'] as String? ?? '').trim();
    final device = devices == null || id.isEmpty
        ? null
        : devices.where((d) => d.id == id).cast<DeviceState?>().firstOrNull;

    final buttons = buttonsOf(device);
    final live = device != null && device.available && buttons.isNotEmpty;
    final ink = resolveInk(t, config['ink'] as String?) ?? t.accent.active;
    final label = (config['label'] as String? ?? '').trim();

    if (device != null && buttons.isEmpty) {
      // Said, rather than drawn as an empty box. A device that publishes no
      // buttons is not a keypad, and the author pointed this at the wrong one.
      return _Says(
        text: '${device.displayName} publishes no buttons.',
        t: t,
      );
    }

    return Semantics(
      container: true,
      label: label.isEmpty ? device?.displayName : label,
      child: Opacity(
        opacity: live ? 1 : .4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label.isNotEmpty || device != null)
              Padding(
                padding: EdgeInsets.only(bottom: t.space.xs),
                child: Text(
                  label.isEmpty ? device!.displayName : label,
                  overflow: TextOverflow.ellipsis,
                  style:
                      t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
                ),
              ),
            Wrap(
              spacing: t.space.xs,
              runSpacing: t.space.xs,
              children: [
                for (final button in buttons)
                  _Button(
                    label: button.label,
                    lit: button.lit,
                    was: button.was,
                    ink: ink,
                    onTap: live
                        ? () => ref
                            .read(devicesProvider.notifier)
                            .command(id, {'press_button': button.number})
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One button, as the device describes it.
typedef KeypadButton = ({int number, String label, bool lit, String? was});

/// The buttons this device says a person can press.
///
/// Two spellings, because plugins send both: a bare number for a Pico, and
/// `{name, number}` for a keypad that has engraving. A bare number still gets a
/// label, because "Button 3" is a thing you can look for on a wall and an
/// unlabelled square is not.
List<KeypadButton> buttonsOf(DeviceState? device) {
  final raw = device?.state['available_buttons'];
  if (raw is! List) return const [];
  final out = <KeypadButton>[];
  for (final entry in raw) {
    int? number;
    String? name;
    if (entry is num) {
      number = entry.toInt();
    } else if (entry is Map) {
      final n = entry['number'];
      if (n is num) number = n.toInt();
      final label = entry['name'];
      if (label is String && label.trim().isNotEmpty) name = label.trim();
    }
    if (number == null) continue;
    final led = device!.state['led_$number'];
    out.add((
      number: number,
      label: buttonLabel(device, number, engraved: name),
      lit: led == true || led == 'on',
      was: device.state['button_$number'] as String?,
    ));
  }
  return out;
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.lit,
    required this.was,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final bool lit;
  final String? was;
  final Color ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      toggled: lit,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: t.radius.smR,
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: t.space.sm, vertical: t.space.sm),
            decoration: BoxDecoration(
              color: lit ? ink.withValues(alpha: .14) : t.surface.raised,
              border: Border.all(
                color: lit ? ink.withValues(alpha: .5) : t.stroke.hairline,
              ),
              borderRadius: t.radius.smR,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The LED. Small and always present, so a keypad whose lights
                // are all off still reads as a keypad rather than as a row of
                // labels.
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: lit ? ink : t.accent.inactive,
                    // The skin decides whether a lit thing blooms at all; a
                    // flat skin gets a flat pip and still reads as lit,
                    // because the fill already said so.
                    boxShadow: lit ? t.glow.halo(ink, blur: 6) : null,
                  ),
                ),
                SizedBox(width: t.space.xs),
                Text(
                  label,
                  style: t.text.bodySmallStyle.copyWith(
                    color: lit ? ink : t.surface.onBase,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Says extends StatelessWidget {
  const _Says({required this.text, required this.t});
  final String text;
  final HcTokens t;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsets.all(t.space.sm),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
          ),
        ),
      );
}
