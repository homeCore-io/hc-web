import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/schema/device_schema.dart';
import '../../design/components/colour_controls.dart';
import '../../design/tokens.dart';

/// A warm↔cool bar you draw, wired to a bulb's colour temperature.
///
/// **Why this is not just a slider pointed at Kelvin.** A slider would work —
/// `color_temp` is numeric and `writableNumber` would offer it. What it could
/// not do is *paint the scale*. This bar's gradient runs blue to amber, and
/// that gradient is a claim about what the numbers mean; putting it over a
/// volume control would be a lie. So the bar takes only `color_temp`, and the
/// picker offers only that.
///
/// **The range is the plugin's** where it gave one, exactly as the slider's is,
/// falling back to the 2000–6500 K the tunable-white bulbs in this house all
/// sit inside. And **it sends when you let go**, for the same reason.
///
/// The bar itself is `design/components/colour_controls.dart` — shared with the
/// device panel, so a temperature picked here and one picked there mean the
/// same thing.
class WarmthElement extends ConsumerStatefulWidget {
  const WarmthElement({super.key, required this.config});

  final Map<String, dynamic> config;

  @override
  ConsumerState<WarmthElement> createState() => _WarmthElementState();
}

class _WarmthElementState extends ConsumerState<WarmthElement> {
  /// 0 cool … 100 warm, while a finger is down. Null otherwise.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final config = widget.config;
    final devices = ref.watch(devicesProvider).value;

    final id = (config['device_id'] as String? ?? '').trim();
    final attribute = (config['attribute'] as String? ?? 'color_temp').trim();
    final device = devices == null || id.isEmpty
        ? null
        : devices.where((d) => d.id == id).cast<DeviceState?>().firstOrNull;

    final spec = device?.schema?.attributes[attribute];
    final promised =
        spec != null && spec.writable && spec.kind == AttributeKind.colorTemp;
    final live = device != null && device.available && promised;

    final min = spec?.hasRange == true ? spec!.min! : kWarmKelvin;
    final max = spec?.hasRange == true ? spec!.max! : kCoolKelvin;

    final kelvin = _kelvinOf(device, attribute);
    final warmth = _dragging ??
        (kelvin == null ? 50.0 : warmthFromKelvin(kelvin, min: min, max: max));

    final label = (config['label'] as String? ?? '').trim();
    final axis = (config['axis'] as String? ?? '') == 'horizontal'
        ? Axis.horizontal
        : Axis.vertical;

    return Semantics(
      slider: true,
      enabled: live,
      label: label.isEmpty ? device?.displayName : label,
      value: kelvin == null ? null : '${kelvin.round()} K',
      child: ExcludeSemantics(
        child: Opacity(
          opacity: live ? 1 : .4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                        // A dash, not a number, when the bulb has not said —
                        // the handle sitting mid-bar would otherwise imply a
                        // temperature nobody reported.
                        kelvin == null && _dragging == null
                            ? '—'
                            : '${_shown(kelvin, min, max).round()} K',
                        style: t.text.captionStyle
                            .copyWith(color: t.surface.onBaseMuted),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: WarmthBar(
                  temp: warmth,
                  axis: axis,
                  enabled: live,
                  onChanged: (v) => setState(() => _dragging = v),
                  onEnd: () {
                    final picked = _dragging;
                    setState(() => _dragging = null);
                    if (picked == null || !live) return;
                    ref.read(devicesProvider.notifier).command(id, {
                      // Whole Kelvin: no bridge wants 2713.4.
                      attribute:
                          kelvinFromWarmth(picked, min: min, max: max).round(),
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What to print: the number being dragged towards, else the bulb's own.
  double _shown(double? kelvin, double min, double max) => _dragging == null
      ? kelvin!
      : kelvinFromWarmth(_dragging!, min: min, max: max);

  /// The bulb's temperature in Kelvin.
  ///
  /// Hue reports mireds (`color_temp_mirek`) and everything else reports
  /// Kelvin; a bar that read only its own attribute would show a dash for half
  /// the bulbs in the house.
  static double? _kelvinOf(DeviceState? d, String attribute) {
    if (d == null) return null;
    final k = d.state[attribute];
    if (k is num && k > 0) return k.toDouble();
    final mirek = d.state['color_temp_mirek'];
    if (mirek is num && mirek > 0) return 1000000 / mirek;
    return null;
  }
}
