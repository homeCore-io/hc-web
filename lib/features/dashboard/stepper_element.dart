import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/card_style.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/schema/device_schema.dart';
import '../../design/tokens.dart';

/// Minus, a number, plus.
///
/// **Where the slider cannot go.** A slider needs a range to mean anything and
/// refuses to work without one — its ends are its whole vocabulary. A stepper
/// needs no range at all: it says *up a bit* and *down a bit*, which is what a
/// thermostat setpoint or a volume actually wants, and which is also the only
/// control available for the writable numbers a plugin registered without
/// bounds. It uses a range where one exists, but only to stop at it.
///
/// **The step is the plugin's** where it named one. A `color_temp` registered
/// with `step: 100` moves in hundreds because that is what the bulb quantises
/// to; a setpoint typically wants a half. The config's step is the fallback,
/// not the authority.
///
/// **It sends per press, not per frame** — there is no drag to coalesce, so
/// each press is one write, and holding is not a gesture this offers. That is
/// deliberate: an auto-repeat on a serial bridge queues faster than the bridge
/// drains.
///
/// The promise rule is the switch's, unchanged — a *registered* writable
/// number, re-checked at the press.
class StepperElement extends ConsumerWidget {
  const StepperElement({super.key, required this.config});

  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value;

    final id = (config['device_id'] as String? ?? '').trim();
    final attribute = (config['attribute'] as String? ?? '').trim();
    final device = devices == null || id.isEmpty
        ? null
        : devices.where((d) => d.id == id).cast<DeviceState?>().firstOrNull;

    final spec = device?.schema?.attributes[attribute];
    final promised = spec != null && spec.writable && spec.kind.isNumeric;
    final reading = _asNumber(device?.state[attribute]);

    // A step of the plugin's, else the page's, else one — never zero, which
    // would give two buttons that do nothing.
    final step = _positive(spec?.step) ??
        _positive(_asNumber(config['step'])) ??
        (spec?.kind == AttributeKind.float ? 0.5 : 1.0);

    // Something has to be there to step FROM. Unlike the switch, this control
    // reads before it writes.
    final live =
        device != null && device.available && promised && reading != null;

    final ink = resolveInk(t, config['ink'] as String?) ?? t.accent.primary;
    final label = (config['label'] as String? ?? '').trim();
    final unit = spec?.unit;

    double? next(int direction) {
      if (!live) return null;
      var v = reading + step * direction;
      if (spec.min != null) v = v < spec.min! ? spec.min! : v;
      if (spec.max != null) v = v > spec.max! ? spec.max! : v;
      // Already at the end: nothing to send, and a button that sends the value
      // the device already holds looks like it worked and did nothing.
      return v == reading ? null : v;
    }

    void send(int direction) {
      final v = next(direction);
      if (v == null) return;
      ref.read(devicesProvider.notifier).command(id, {
        attribute: spec!.kind == AttributeKind.float ? v : v.round(),
      });
    }

    return Semantics(
      enabled: live,
      label: label.isEmpty ? device?.displayName : label,
      value: reading == null ? null : _trim(reading),
      child: ExcludeSemantics(
        child: Opacity(
          opacity: live ? 1 : .4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Key(
                icon: Icons.remove,
                ink: ink,
                onTap: next(-1) == null ? null : () => send(-1),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: t.space.sm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      // A dash rather than a zero: with nothing read, zero
                      // would be a claim about the device.
                      reading == null ? '—' : '${_trim(reading)}${unit ?? ''}',
                      style: t.text.titleStyle.copyWith(
                        color: t.surface.onBase,
                        fontFeatures: t.numericFontFeatures,
                      ),
                    ),
                    if (label.isNotEmpty)
                      Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: t.text.captionStyle
                            .copyWith(color: t.surface.onBaseMuted),
                      ),
                  ],
                ),
              ),
              _Key(
                icon: Icons.add,
                ink: ink,
                onTap: next(1) == null ? null : () => send(1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static double? _positive(double? v) => v != null && v > 0 ? v : null;

  static double? _asNumber(Object? raw) {
    if (raw is num) return raw.isFinite ? raw.toDouble() : null;
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

class _Key extends StatelessWidget {
  const _Key({required this.icon, required this.ink, required this.onTap});

  final IconData icon;
  final Color ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final on = onTap != null;
    return GestureDetector(
      // Opaque, so the whole key is the target and not only the glyph.
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.surface.raised,
          border: Border.all(color: t.stroke.hairline),
          borderRadius: t.radius.smR,
        ),
        // Dimmed at the end of the range rather than hidden: a key that
        // disappears makes the control jump under the finger.
        child: Icon(icon, size: 18, color: on ? ink : t.surface.onBaseMuted),
      ),
    );
  }
}
