import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/schema/device_schema.dart';
import '../../design/tokens.dart';

/// A thermostat, drawn as a dial.
///
/// **A setpoint only means something against the reading.** Two numbers side by
/// side say what each one is and nothing about the pair: whether the house is
/// working, which way, and how far it has to go. On a ring all three are one
/// picture — the arc reaches the reading, the faint part after it is the gap to
/// the target, and the tick is where the target sits. That is the whole reason
/// this is not a `device_reading` and a `stepper` next to each other.
///
/// **The colour is the direction, not the temperature.** Amber when it is
/// heating, blue when it is cooling, neither when it has arrived. A dial that
/// coloured by *value* would be telling you it is warm in a room you can feel.
///
/// The target obeys the switch's rule — only a registered writable, checked
/// again at the press — because raising a setpoint is a write to the house.
class ThermostatElement extends ConsumerWidget {
  const ThermostatElement({super.key, required this.config});

  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value;

    final id = (config['device_id'] as String? ?? '').trim();
    final device = devices == null || id.isEmpty
        ? null
        : devices.where((d) => d.id == id).cast<DeviceState?>().firstOrNull;

    final readKey = (config['attribute'] as String? ?? '').trim();
    final setKey = (config['target'] as String? ?? '').trim();

    final now = _number(device?.state[_firstOf(device, readKey, _readNames)]);
    final targetName = _firstOf(device, setKey, _targetNames);
    final target = _number(device?.state[targetName]);

    final spec = device?.schema?.attributes[targetName];
    final canSet = spec != null && spec.writable && spec.kind.isNumeric;
    final live = device != null && device.available && canSet;

    // The dial's range. The plugin's where it gave one — a thermostat that says
    // 45–95 is describing itself — else the span people actually live in.
    final min = spec?.hasRange == true ? spec!.min! : 55.0;
    final max = spec?.hasRange == true ? spec!.max! : 85.0;
    final step = spec?.step ?? 1.0;
    final unit = spec?.unit ?? '°';

    final label = (config['label'] as String? ?? '').trim();

    return Semantics(
      slider: true,
      enabled: live,
      label: label.isEmpty ? device?.displayName : label,
      value: target == null ? null : '${_trim(target)}$unit',
      child: ExcludeSemantics(
        child: Opacity(
          opacity: device != null && device.available ? 1 : .4,
          child: LayoutBuilder(builder: (context, box) {
            final compact = box.maxHeight < 210;
            return Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: _Dial(
                    now: now,
                    target: target,
                    min: min,
                    max: max,
                    unit: unit,
                    t: t,
                  ),
                ),
                if (!compact) SizedBox(height: t.space.sm),
                if (!compact)
                  _Setpoint(
                    target: target,
                    unit: unit,
                    onStep: live && target != null
                        ? (by) => ref.read(devicesProvider.notifier).command(
                              id,
                              {
                                targetName: _clamp(
                                  target + by * step,
                                  min,
                                  max,
                                  whole: spec.kind == AttributeKind.integer,
                                ),
                              },
                            )
                        : null,
                    t: t,
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }

  /// The attribute the author named, or the first conventional one the device
  /// actually reports. A thermostat that calls its reading `temperature` and
  /// one that calls it `current_temperature` are the same thermostat.
  static String _firstOf(DeviceState? d, String named, List<String> names) {
    if (named.isNotEmpty) return named;
    if (d == null) return names.first;
    for (final n in names) {
      if (d.state.containsKey(n)) return n;
    }
    return names.first;
  }

  static const _readNames = ['current_temperature', 'temperature'];
  static const _targetNames = [
    'target_temperature',
    'setpoint',
    'heating_setpoint',
    'target_temp',
  ];

  static double? _number(Object? raw) {
    if (raw is num) return raw.isFinite ? raw.toDouble() : null;
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  static num _clamp(double v, double min, double max, {required bool whole}) {
    final clamped = v < min ? min : (v > max ? max : v);
    return whole ? clamped.round() : clamped;
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

/// The ring: the reading, the gap, and the target's own mark.
class _Dial extends StatelessWidget {
  const _Dial({
    required this.now,
    required this.target,
    required this.min,
    required this.max,
    required this.unit,
    required this.t,
  });

  final double? now;
  final double? target;
  final double min;
  final double max;
  final String unit;
  final HcTokens t;

  @override
  Widget build(BuildContext context) {
    final heating = now != null && target != null && target! > now! + 0.2;
    final cooling = now != null && target != null && target! < now! - 0.2;
    final ink = heating
        ? t.accent.active
        : cooling
            ? t.accent.primary
            : t.surface.onBaseMuted;

    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: _DialPainter(
              now: _fraction(now),
              target: _fraction(target),
              track: t.accent.inactive,
              ink: ink,
              mark: t.surface.onBase,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                // A dash, not a zero. Zero degrees is a claim about the room.
                now == null ? '—' : '${ThermostatElement._trim(now!)}$unit',
                style: t.text.displayStyle.copyWith(
                  color: t.surface.onBase,
                  fontFeatures: t.numericFontFeatures,
                ),
              ),
              SizedBox(height: t.space.xs),
              Text(
                target == null
                    ? 'No target'
                    : heating
                        ? 'Heating to ${ThermostatElement._trim(target!)}$unit'
                        : cooling
                            ? 'Cooling to ${ThermostatElement._trim(target!)}$unit'
                            : 'Holding at ${ThermostatElement._trim(target!)}$unit',
                textAlign: TextAlign.center,
                style: t.text.captionStyle.copyWith(color: ink),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double? _fraction(double? v) => v == null || max <= min
      ? null
      : ((v - min) / (max - min)).clamp(0.0, 1.0);
}

class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.now,
    required this.target,
    required this.track,
    required this.ink,
    required this.mark,
  });

  final double? now;
  final double? target;
  final Color track;
  final Color ink;
  final Color mark;

  /// Three quarters of a turn, opening at the bottom — the gap is where a
  /// thermostat's own display puts its buttons, and a closed ring reads as a
  /// gauge of something with no ends.
  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final stroke = math.max(6.0, side * 0.075);
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (side - stroke) / 2,
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, _start, _sweep, false, base..color = track);

    if (now != null) {
      canvas.drawArc(rect, _start, _sweep * now!, false, base..color = ink);
      // The gap between the reading and the target: the only part of this that
      // says the system is working rather than idling.
      if (target != null && (target! - now!).abs() > 0.001) {
        final from = math.min(now!, target!);
        final to = math.max(now!, target!);
        canvas.drawArc(
          rect,
          _start + _sweep * from,
          _sweep * (to - from),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..color = ink.withValues(alpha: 0.3),
        );
      }
    }

    if (target != null) {
      final angle = _start + _sweep * target!;
      final centre = rect.center;
      final outer = rect.width / 2 + stroke / 2;
      final inner = rect.width / 2 - stroke / 2;
      canvas.drawLine(
        centre + Offset(math.cos(angle), math.sin(angle)) * inner,
        centre + Offset(math.cos(angle), math.sin(angle)) * outer,
        Paint()
          ..color = mark
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.now != now || old.target != target || old.ink != ink;
}

/// Minus, the target, plus. A stepper rather than a slider, because a setpoint
/// is nudged rather than aimed — and because a thermostat that gave no range
/// would leave a slider with ends that mean nothing.
class _Setpoint extends StatelessWidget {
  const _Setpoint({
    required this.target,
    required this.unit,
    required this.onStep,
    required this.t,
  });

  final double? target;
  final String unit;
  final void Function(int by)? onStep;
  final HcTokens t;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Key(
              icon: Icons.remove,
              onTap: onStep == null ? null : () => onStep!(-1),
              t: t),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: t.space.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  target == null ? '—' : ThermostatElement._trim(target!),
                  style: t.text.titleStyle.copyWith(
                    color: t.surface.onBase,
                    fontFeatures: t.numericFontFeatures,
                  ),
                ),
                Text('$unit target',
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted)),
              ],
            ),
          ),
          _Key(
              icon: Icons.add,
              onTap: onStep == null ? null : () => onStep!(1),
              t: t),
        ],
      );
}

class _Key extends StatelessWidget {
  const _Key({required this.icon, required this.onTap, required this.t});

  final IconData icon;
  final VoidCallback? onTap;
  final HcTokens t;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.surface.raised,
            border: Border.all(color: t.stroke.hairline),
            borderRadius: t.radius.smR,
          ),
          child: Icon(
            icon,
            size: 16,
            color: onTap == null ? t.surface.onBaseMuted : t.surface.onBase,
          ),
        ),
      );
}
