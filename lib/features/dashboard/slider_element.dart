import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/card_style.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/schema/device_schema.dart';
import '../../design/tokens.dart';

/// A slider you draw, wired to a number a device promised to accept.
///
/// The switch's rules apply unchanged — only a registered `writable` counts,
/// and it refuses to send if the promise is not there when the drag ends. See
/// `toggle_element.dart` for why an inferred one is not good enough.
///
/// Two things are its own:
///
/// **The range comes from the plugin, not from the page.** A schema that says
/// 0–255 is the device describing itself; a range typed into a config is the
/// author guessing, and the two disagree the moment a bulb is replaced. The
/// config range exists only for the devices that registered a writable number
/// and no bounds, and the picker says which case you are in.
///
/// **It sends when you let go.** A slider that commanded on every frame would
/// put sixty writes a second onto a plugin that is often a serial bridge or a
/// cloud API — hc-lutron and hc-hue would both queue and lag, and the handle
/// would then fight the device's own echo. So the handle follows your finger
/// locally and the house hears once.
class SliderElement extends ConsumerStatefulWidget {
  const SliderElement({super.key, required this.config});

  final Map<String, dynamic> config;

  @override
  ConsumerState<SliderElement> createState() => _SliderElementState();
}

class _SliderElementState extends ConsumerState<SliderElement> {
  /// Where the handle is while a finger is on it.
  ///
  /// Null the rest of the time, so the slider shows the house rather than the
  /// last thing anybody dragged — including when somebody else, or a rule,
  /// moves the device.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final config = widget.config;
    final devices = ref.watch(devicesProvider).value;

    final id = (config['device_id'] as String? ?? '').trim();
    final attribute = (config['attribute'] as String? ?? '').trim();
    final device = devices == null || id.isEmpty
        ? null
        : devices.where((d) => d.id == id).cast<DeviceState?>().firstOrNull;

    final spec = device?.schema?.attributes[attribute];
    final promised = spec != null && spec.writable && spec.kind.isNumeric;

    // Read once, so nothing later depends on a `!` earlier in the tree having
    // promoted `spec` — which is how the integer check below came to look
    // redundant to the analyser while still being the thing that matters.
    final unit = spec?.unit;
    final isInteger = spec?.kind == AttributeKind.integer;

    final (min, max) = _bounds(spec, config);
    final ranged = min != null && max != null && max > min;
    final live = device != null && device.available && promised && ranged;

    final reading = _asNumber(device?.state[attribute]);
    final value = (_dragging ?? reading ?? min ?? 0).clamp(min ?? 0, max ?? 1);

    final ink = resolveInk(t, config['ink'] as String?) ?? t.accent.active;
    final label = (config['label'] as String? ?? '').trim();

    // Why this slider cannot be dragged, in the fewest words that name the
    // mistake. A dimmed control showing `—` is honest about having no reading
    // and silent about the reason, so a slider pointed at an attribute the
    // device does not have looks exactly like one whose device is slow — and
    // the person who has to tell them apart is holding the inspector.
    final why = devices == null
        ? null
        : device == null
            ? (id.isEmpty ? 'no device' : 'no such device')
            : attribute.isEmpty
                ? 'no attribute'
                : !device.available
                    ? 'offline'
                    : spec == null
                        ? 'no $attribute'
                        : !spec.kind.isNumeric
                            ? 'not a number'
                            : !spec.writable
                                ? 'read-only'
                                : !ranged
                                    ? 'no range'
                                    : null;

    return Semantics(
      slider: true,
      enabled: live,
      label: label.isEmpty ? device?.displayName : label,
      value: reading == null ? null : _trim(reading),
      child: ExcludeSemantics(
        child: Opacity(
          opacity: live ? 1 : .4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Shown whenever this element is pointed at something, not only
              // when there is a reading. With no reading and no readout the
              // handle sits at the minimum and IMPLIES zero, which is the
              // claim the dash exists to avoid making.
              if (label.isNotEmpty || attribute.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: t.space.xs),
                  child: Row(
                    children: [
                      if (label.isNotEmpty)
                        Flexible(
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: t.text.bodySmallStyle
                                .copyWith(color: t.surface.onBase),
                          ),
                        ),
                      const Spacer(),
                      Text(
                        // The dragged number while dragging: the point of
                        // showing it is to aim, and the device's own value has
                        // not heard about the drag yet.
                        reading == null && _dragging == null
                            // The dash stays for a control that is wired
                            // correctly and simply has no reading yet; the
                            // words are for one that never will.
                            ? (why ?? '—')
                            : '${_trim(_dragging ?? reading!)}'
                                '${unit == null ? '' : ' $unit'}',
                        style: t.text.captionStyle
                            .copyWith(color: t.surface.onBaseMuted),
                      ),
                    ],
                  ),
                ),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: ink,
                  inactiveTrackColor: t.accent.inactive,
                  thumbColor: t.surface.onBase,
                  overlayColor: ink.withValues(alpha: .12),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: value.toDouble(),
                  min: (min ?? 0).toDouble(),
                  max: (max ?? 1).toDouble(),
                  // The plugin's step when it named one. Without it a 0–255
                  // brightness would send fractions no device wants.
                  divisions: _divisions(min, max, spec?.step),
                  onChanged: live ? (v) => setState(() => _dragging = v) : null,
                  onChangeEnd: live
                      ? (v) {
                          setState(() => _dragging = null);
                          ref.read(devicesProvider.notifier).command(id, {
                            // Whole numbers for an integer attribute: a
                            // brightness of 61.7 is a value no bridge accepts
                            // and some reject outright.
                            attribute: isInteger ? v.round() : v,
                          });
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The plugin's range, or the page's when it gave none.
  static (double?, double?) _bounds(
    AttributeSchema? spec,
    Map<String, dynamic> config,
  ) {
    if (spec != null && spec.hasRange) return (spec.min, spec.max);
    return (_asNumber(config['min']), _asNumber(config['max']));
  }

  static int? _divisions(double? min, double? max, double? step) {
    if (min == null || max == null || step == null || step <= 0) return null;
    final n = ((max - min) / step).round();
    return n > 0 && n <= 1000 ? n : null;
  }

  static double? _asNumber(Object? raw) {
    if (raw is num) return raw.isFinite ? raw.toDouble() : null;
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}
