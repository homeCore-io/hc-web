import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/thermostat_prefs_provider.dart';
import '../../design/tokens.dart';
import 'home_edit_button.dart';

/// A thermostat, as a Nest-style dial (when it is the room's whole story) or a
/// compact decorative gauge (when it shares the room with other devices).
///
/// A temperature is a fact; a temperature you can drag to is a control. The dial
/// colours itself by what it is doing — blue cooling, warm heating — so the room
/// says its climate at a glance.
class HomeThermostat extends ConsumerStatefulWidget {
  const HomeThermostat({super.key, required this.device});

  final DeviceState device;

  @override
  ConsumerState<HomeThermostat> createState() => _HomeThermostatState();
}

const _min = 50.0, _max = 90.0;

class _ModeStyle {
  const _ModeStyle(this.colour, this.verb);
  final Color colour;
  final String verb;
}

class _HomeThermostatState extends ConsumerState<HomeThermostat> {
  bool _dragging = false;
  late double _sp;

  @override
  void initState() {
    super.initState();
    _sp = _setpointOf(widget.device);
  }

  @override
  void didUpdateWidget(covariant HomeThermostat old) {
    super.didUpdateWidget(old);
    if (!_dragging) _sp = _setpointOf(widget.device);
  }

  static double _setpointOf(DeviceState d) =>
      ((d.state['setpoint'] as num?)?.toDouble() ?? 70).clamp(_min, _max);

  DevicesNotifier get _notifier => ref.read(devicesProvider.notifier);

  void _setSp(double v) {
    setState(() => _sp = v.clamp(_min, _max));
    _notifier.command(widget.device.id, {
      'command': 'set_setpoint',
      'value': (_sp * 2).round() / 2,
    });
  }

  void _setMode(String mode) => _notifier
      .command(widget.device.id, {'command': 'set_mode', 'value': mode});

  _ModeStyle _style(String mode, String callFor) {
    // Colour follows what it is actually doing when it is doing something,
    // otherwise the configured mode.
    final key = callFor == 'cool' || callFor == 'heat' ? callFor : mode;
    return switch (key) {
      'cool' => const _ModeStyle(Color(0xFF5AA9E6), 'Cooling'),
      'heat' => _ModeStyle(HcTokens.of(context).accent.warn, 'Heating'),
      'auto' => const _ModeStyle(Color(0xFF3EC07A), 'Auto'),
      _ => _ModeStyle(HcTokens.of(context).surface.onBaseMuted, 'Off'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.device.state;
    final cur = (s['current_temperature'] as num?)?.toDouble();
    final mode = (s['mode'] as String?) ?? 'off';
    final callFor = (s['call_for'] as String?) ?? 'idle';
    final style = _style(mode, callFor);
    final active = callFor == 'cool' || callFor == 'heat';
    final large = ref.watch(thermostatLargeProvider).contains(widget.device.id);

    return large
        ? _full(context, cur, mode, style, active)
        : _compact(context, cur, mode, style, active);
  }

  void _setLarge(bool large) => ref
      .read(thermostatLargeProvider.notifier)
      .setLarge(widget.device.id, large);

  String _fmt(double v) =>
      (v * 2).round() % 2 == 0 ? '${v.round()}°' : '${(v * 2).round() / 2}°';

  // -- full dial -----------------------------------------------------------

  Widget _full(BuildContext context, double? cur, String mode, _ModeStyle style,
      bool active) {
    final t = HcTokens.of(context);
    return Padding(
      padding:
          EdgeInsets.fromLTRB(t.space.md, t.space.xs, t.space.md, t.space.lg),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              HomeEditButton(deviceId: widget.device.id),
              IconButton(
                icon: const Icon(Icons.unfold_less, size: 18),
                tooltip: 'Show compact',
                color: t.surface.onBaseMuted,
                visualDensity: VisualDensity.compact,
                onPressed: () => _setLarge(false),
              ),
            ],
          ),
          SizedBox(
            width: 208,
            height: 208,
            child: GestureDetector(
              onPanStart: (_) => _dragging = true,
              onPanUpdate: (d) => _dragFromDial(d.localPosition, 208),
              onPanEnd: (_) => _dragging = false,
              child: CustomPaint(
                painter: _DialPainter(
                  frac: (_sp - _min) / (_max - _min),
                  colour: style.colour,
                  track: t.stroke.hairline,
                  stroke: 11,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        active ? style.verb.toUpperCase() : mode.toUpperCase(),
                        style: t.text.captionStyle.copyWith(
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w700,
                            color: style.colour),
                      ),
                      Text(_fmt(_sp),
                          style: TextStyle(
                              fontSize: t.text.scaled(52),
                              fontWeight: FontWeight.w300,
                              letterSpacing: -2,
                              height: 1.05,
                              color: t.surface.onBase,
                              fontFeatures: t.numericFontFeatures)),
                      if (cur != null)
                        Text('Now ${cur.toStringAsFixed(1)}°',
                            style: t.text.bodySmallStyle.copyWith(
                                color: t.surface.onBaseMuted,
                                fontFeatures: t.numericFontFeatures)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: t.space.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Step(glyph: '−', onTap: () => _setSp(_sp - 0.5)),
              SizedBox(width: t.space.md),
              SizedBox(
                width: 108,
                child: Text(
                  active ? '${style.verb} to ${_fmt(_sp)}' : 'Off',
                  textAlign: TextAlign.center,
                  style: t.text.bodySmallStyle.copyWith(
                      fontWeight: FontWeight.w600, color: style.colour),
                ),
              ),
              SizedBox(width: t.space.md),
              _Step(glyph: '+', onTap: () => _setSp(_sp + 0.5)),
            ],
          ),
          SizedBox(height: t.space.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final m in const ['off', 'cool', 'heat', 'auto'])
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: t.space.xs),
                  child: _ModeChip(
                    label: m[0].toUpperCase() + m.substring(1),
                    selected: mode == m,
                    colour: _style(m, 'idle').colour,
                    onTap: () => _setMode(m),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _dragFromDial(Offset local, double size) {
    final r = size / 2;
    final dx = local.dx - r, dy = local.dy - r;
    var a = math.atan2(dy, dx) * 180 / math.pi;
    if (a < 0) a += 360;
    if (a < 135) a += 360; // map into 135..495
    final frac = a > 405 ? (a - 405 < 495 - a ? 1.0 : 0.0) : (a - 135) / 270;
    _setSp(_min + frac.clamp(0.0, 1.0) * (_max - _min));
  }

  // -- compact gauge -------------------------------------------------------

  Widget _compact(BuildContext context, double? cur, String mode,
      _ModeStyle style, bool active) {
    final t = HcTokens.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  style.colour.withValues(alpha: 0.16),
                  Colors.transparent
                ],
                stops: const [0, 0.6],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: t.space.md, vertical: t.space.sm),
          child: Row(
            children: [
              // Tapping the gauge/name expands to the full dial and remembers
              // it; the steppers keep working without expanding.
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _setLarge(true),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: CustomPaint(
                            painter: _DialPainter(
                              frac: (_sp - _min) / (_max - _min),
                              colour: style.colour,
                              track: t.stroke.hairline,
                              stroke: 4,
                            ),
                            child: Center(
                              child: Text(_fmt(_sp),
                                  style: t.text.bodySmallStyle.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: style.colour,
                                      fontFeatures: t.numericFontFeatures)),
                            ),
                          ),
                        ),
                        SizedBox(width: t.space.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(widget.device.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.text.bodyStyle.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: t.surface.onBase)),
                              Text(
                                active
                                    ? '${style.verb}${cur != null ? ' · now ${cur.toStringAsFixed(1)}°' : ''}'
                                    : mode[0].toUpperCase() + mode.substring(1),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.text.captionStyle.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: style.colour,
                                    fontFeatures: t.numericFontFeatures),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              HomeEditButton(deviceId: widget.device.id),
              SizedBox(width: t.space.xs),
              _Step(glyph: '−', small: true, onTap: () => _setSp(_sp - 0.5)),
              SizedBox(width: t.space.sm),
              SizedBox(
                width: 34,
                child: Text(_fmt(_sp),
                    textAlign: TextAlign.center,
                    style: t.text.subtitleStyle.copyWith(
                        fontWeight: FontWeight.w700,
                        color: t.surface.onBase,
                        fontFeatures: t.numericFontFeatures)),
              ),
              SizedBox(width: t.space.sm),
              _Step(glyph: '+', small: true, onTap: () => _setSp(_sp + 0.5)),
            ],
          ),
        ),
      ],
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.frac,
    required this.colour,
    required this.track,
    required this.stroke,
  });

  final double frac;
  final Color colour;
  final Color track;
  final double stroke;

  static const _start = 135 * math.pi / 180;
  static const _sweep = 270 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, _start, _sweep, false, base);

    final prog = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = null
      ..color = colour
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.25);
    canvas.drawArc(rect, _start, _sweep * frac.clamp(0.0, 1.0), false, prog);
    canvas.drawArc(rect, _start, _sweep * frac.clamp(0.0, 1.0), false,
        prog..maskFilter = null);

    // Handle.
    final a = _start + _sweep * frac.clamp(0.0, 1.0);
    final r = (size.width - stroke) / 2;
    final c = Offset(
        size.width / 2 + r * math.cos(a), size.height / 2 + r * math.sin(a));
    canvas.drawCircle(c, stroke * 0.55 + 3, Paint()..color = Colors.white);
    canvas.drawCircle(c, stroke * 0.55, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.frac != frac || old.colour != colour;
}

class _Step extends StatelessWidget {
  const _Step({required this.glyph, required this.onTap, this.small = false});
  final String glyph;
  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final d = small ? 29.0 : 46.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: d,
        height: d,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: t.stroke.hairline),
          color: t.surface.sunken,
        ),
        child: Text(glyph,
            style: TextStyle(
                fontSize: small ? 16 : 20,
                height: 1,
                fontWeight: FontWeight.w500,
                color: t.surface.onBase)),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.colour,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: t.space.md, vertical: t.space.xs + 1),
        decoration: BoxDecoration(
          color: selected ? colour.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: t.radius.pillR,
          border: Border.all(color: selected ? colour : t.stroke.hairline),
        ),
        child: Text(label,
            style: t.text.bodySmallStyle.copyWith(
                fontWeight: FontWeight.w600,
                color: selected ? colour : t.surface.onBaseMuted)),
      ),
    );
  }
}
