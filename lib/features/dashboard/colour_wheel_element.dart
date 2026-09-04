import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/devices/color_space.dart' show rgbToXy;
import '../../core/devices/presentation.dart' show lightColorOf;
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/schema/device_schema.dart';
import '../../design/components/colour_controls.dart';
import '../../design/tokens.dart';

/// A colour wheel you draw, wired to a bulb that promised to accept one.
///
/// **It is the device panel's wheel, not a second one.** `ColourWheel` lives in
/// `design/components/colour_controls.dart` and both surfaces use it, so the
/// same bulb picks the same colour whichever one you touch. Two wheels with
/// their own ideas of where hue starts would be two houses.
///
/// **The switch's promise rule applies unchanged**: only a *registered*
/// writable of a colour kind counts, checked again when the finger lifts.
/// See `toggle_element.dart` for why an inferred `writable` is not enough.
///
/// **It sends the shape the attribute is.** A `color_xy` takes `{x, y}`; a
/// `color_rgb` takes `{r, g, b}`. These are not interchangeable and a plugin
/// handed the wrong one rejects the write — which is the whole reason the
/// element carries the kind through rather than picking one and hoping.
///
/// **It sends when you let go**, for the reason the slider does: a wheel that
/// commanded on every frame would put sixty writes a second onto a bridge.
class ColourWheelElement extends ConsumerStatefulWidget {
  const ColourWheelElement(
      {super.key, required this.config, this.editing = false});

  final Map<String, dynamic> config;

  /// True in the designer, where an element that takes itself away is an
  /// element you cannot arrange.
  final bool editing;

  @override
  ConsumerState<ColourWheelElement> createState() => _ColourWheelElementState();
}

class _ColourWheelElementState extends ConsumerState<ColourWheelElement> {
  /// Where the handle is while a finger is on it. Null the rest of the time, so
  /// the wheel shows the bulb rather than the last thing anybody dragged.
  (double hue, double sat)? _dragging;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final config = widget.config;
    final devices = ref.watch(devicesProvider).value;

    final id = (config['device_id'] as String? ?? '').trim();
    final attribute = (config['attribute'] as String? ?? 'color_xy').trim();
    final device = devices == null || id.isEmpty
        ? null
        : devices.where((d) => d.id == id).cast<DeviceState?>().firstOrNull;

    final spec = device?.schema?.attributes[attribute];
    final kind = spec?.kind;
    final promised = spec != null &&
        spec.writable &&
        (kind == AttributeKind.colorXy || kind == AttributeKind.colorRgb);
    final live = device != null && device.available && promised;

    // **A control for something this light cannot do is not a control.**
    //
    // The Office's Overhead has no colour and no colour temperature, so a
    // panel aimed at it drew a wheel and a warmth bar that could never move.
    // John: *"color wheel and warmth are showing for lights that don't
    // support those features."* On a page it takes itself away; in the
    // designer it stays, because a placement you cannot see is a placement
    // you cannot arrange.
    if (!promised && !widget.editing) {
      return const SizedBox.shrink();
    }

    // The bulb's own colour, read the same way every other surface reads it.
    final shown = device == null ? null : lightColorOf(device);
    final hsv = HSVColor.fromColor(shown ?? const Color(0xFFF0C070));
    final hue = _dragging?.$1 ?? hsv.hue;
    final sat = _dragging?.$2 ?? (shown == null ? 0.6 : hsv.saturation);

    final label = (config['label'] as String? ?? '').trim();

    return Semantics(
      enabled: live,
      label: label.isEmpty ? device?.displayName : label,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: live ? 1 : .4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: t.space.xs),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style:
                        t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
                  ),
                ),
              Expanded(
                child: ColourWheel(
                  hue: hue,
                  sat: sat.clamp(0.0, 1.0),
                  enabled: live,
                  onChanged: (h, s) => setState(() => _dragging = (h, s)),
                  onEnd: () {
                    final picked = _dragging;
                    setState(() => _dragging = null);
                    if (picked == null || !live) return;
                    ref
                        .read(devicesProvider.notifier)
                        .command(id, {attribute: _payload(kind!, picked)});
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The shape this attribute is, not the shape this element prefers.
  static Map<String, num> _payload(AttributeKind kind, (double, double) hs) {
    final c = HSVColor.fromAHSV(1, hs.$1, hs.$2, 1).toColor();
    if (kind == AttributeKind.colorRgb) {
      return {
        'r': (c.r * 255).round(),
        'g': (c.g * 255).round(),
        'b': (c.b * 255).round(),
      };
    }
    final (x, y) = rgbToXy(c);
    return {'x': x, 'y': y};
  }
}
