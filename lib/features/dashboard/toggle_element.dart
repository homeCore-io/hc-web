import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/card_style.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/schema/device_schema.dart';
import '../../design/tokens.dart';

/// A switch you draw, wired to a device that promised to accept one.
///
/// **The first element that writes.** Everything placeable until now showed the
/// house; this changes it, and that difference is the whole reason for the care
/// below.
///
/// **It only offers what a plugin registered.** `attribute_policy.dart` is
/// explicit that an *inferred* `writable` is this app's opinion rather than a
/// promise, and that attribute-style writes are not universal —
/// `hc-sonos::execute_command` dispatches on an `action` and rejects
/// `{"muted": true}` outright. A drawn switch built on that inference would
/// look right, send, and change nothing, on a page somebody trusts. So the
/// guard is enforced twice: the picker offers only registered writable
/// booleans, and this refuses to send if the promise is not there when the tap
/// arrives — a device can re-register between authoring and use.
///
/// The send itself goes through `DevicesNotifier.command`, which already
/// applies optimistically and puts it back if it fails. Nothing here reimplements
/// that: a control that rolled back differently from the rest of the app would
/// be a second opinion about what the house is doing.
class ToggleElement extends ConsumerWidget {
  const ToggleElement({super.key, required this.config});

  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value;

    final id = (config['device_id'] as String? ?? '').trim();
    final attribute = (config['attribute'] as String? ?? 'on').trim();
    final device = devices == null || id.isEmpty
        ? null
        : devices.where((d) => d.id == id).cast<DeviceState?>().firstOrNull;

    final promised = _accepts(device, attribute);
    final on = device?.state[attribute] == true;
    final live = device != null && device.available && promised;

    final ink = resolveInk(t, config['ink'] as String?) ?? t.accent.success;
    final label = (config['label'] as String? ?? '').trim();

    return Semantics(
      toggled: on,
      enabled: live,
      label: label.isEmpty ? device?.displayName : label,
      child: GestureDetector(
        // Opaque, or only the track itself is tappable and the label beside it
        // — and the space the element was dragged out to — do nothing. A
        // control with a dead half is worse than a small one.
        behavior: HitTestBehavior.opaque,
        onTap: live
            ? () =>
                ref.read(devicesProvider.notifier).command(id, {attribute: !on})
            : null,
        child: Opacity(
          // Said, not implied. A switch that looks live and does nothing is
          // worse than one that looks unavailable, because the first teaches
          // somebody the house is broken.
          opacity: live ? 1 : .4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Track(on: on, ink: ink, t: t),
              if (label.isNotEmpty) ...[
                SizedBox(width: t.space.sm),
                Flexible(
                  // Excluded: the Semantics above already names the control,
                  // and without this a screen reader says "Hall lamp, Hall
                  // lamp" — the wrapper's label and the visible words both
                  // reaching it.
                  child: ExcludeSemantics(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: t.text.bodyStyle.copyWith(color: t.surface.onBase),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Did the plugin promise this write?
  ///
  /// A registered schema only. No schema means the device never said, and this
  /// answers no rather than guessing — see the class doc.
  static bool _accepts(DeviceState? d, String attribute) {
    final spec = d?.schema?.attributes[attribute];
    return spec != null && spec.writable && spec.kind == AttributeKind.bool_;
  }
}

class _Track extends StatelessWidget {
  const _Track({required this.on, required this.ink, required this.t});

  final bool on;
  final Color ink;
  final HcTokens t;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: t.motion.d(t.motion.fast),
        curve: t.motion.curve,
        width: 44,
        height: 26,
        decoration: BoxDecoration(
          color: on ? ink : t.accent.inactive,
          borderRadius: t.radius.pillR,
        ),
        child: AnimatedAlign(
          duration: t.motion.d(t.motion.fast),
          curve: t.motion.curve,
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: on ? t.accent.onPrimary : t.surface.onBaseMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      );
}
