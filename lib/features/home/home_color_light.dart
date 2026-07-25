import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/devices/color_space.dart' show rgbToXy;
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import 'home_edit_button.dart';

/// A colour / tunable-white light, as an expressive row that opens a real
/// control — a colour wheel, brightness, a warm↔cool temperature bar, presets.
///
/// A colour bulb is the one device a bare toggle most obviously fails: its whole
/// point is the light it makes. Collapsed it is still a row (lit its real
/// colour, a swatch, a toggle); tapped, it unfolds the controls in place.
class HomeColorLight extends ConsumerStatefulWidget {
  const HomeColorLight({super.key, required this.device});

  final DeviceState device;

  @override
  ConsumerState<HomeColorLight> createState() => _HomeColorLightState();
}

// Tunable-white range, Kelvin. Warm end first.
const _kWarm = 2000.0, _kCool = 6500.0;

class _HomeColorLightState extends ConsumerState<HomeColorLight> {
  bool _open = false;
  bool _dragging = false;

  // Working colour state, seeded from the device and kept live while dragging so
  // the wheel does not stutter against round-trips.
  late double _hue, _sat, _bri, _temp; // temp 0=cool .. 100=warm
  late bool _white;

  @override
  void initState() {
    super.initState();
    _seed();
  }

  @override
  void didUpdateWidget(covariant HomeColorLight old) {
    super.didUpdateWidget(old);
    if (!_dragging) _seed();
  }

  void _seed() {
    final s = widget.device.state;
    _bri = ((s['brightness_pct'] as num?)?.toDouble()) ??
        (levelOf(widget.device) ?? 1) * 100;
    final mirek = s['color_temp_mirek'] as num?;
    final xy = s['color_xy'];
    // Hue reports both; treat a real xy as "colour", else white.
    _white = xy == null && mirek != null;
    final c = lightColorOf(widget.device) ?? const Color(0xFFF0C070);
    final hsv = HSVColor.fromColor(c);
    _hue = hsv.hue;
    _sat = _white ? 0.6 : hsv.saturation.clamp(0.05, 1.0);
    if (mirek != null && mirek > 0) {
      final k = (1000000 / mirek).clamp(_kWarm, _kCool);
      _temp = (_kCool - k) / (_kCool - _kWarm) * 100;
    } else {
      _temp = 40;
    }
  }

  DevicesNotifier get _notifier => ref.read(devicesProvider.notifier);

  Color get _color => _white
      ? _whiteColor(_temp)
      : HSVColor.fromAHSV(1, _hue, _sat, 1).toColor();

  void _commitColour() {
    final (x, y) = rgbToXy(HSVColor.fromAHSV(1, _hue, _sat, 1).toColor());
    _notifier.command(widget.device.id, {
      'on': true,
      'color_xy': {'x': x, 'y': y},
    });
  }

  void _commitTemp() {
    final k = _kCool - _temp / 100 * (_kCool - _kWarm);
    _notifier.command(widget.device.id, {'on': true, 'color_temp': k.round()});
  }

  void _commitBrightness() => _notifier
      .command(widget.device.id, {'on': true, 'brightness_pct': _bri.round()});

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final on = widget.device.available && isOn(widget.device);
    final colour = on ? _color : t.surface.onBaseMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The row.
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: t.space.md, vertical: t.space.sm + 1),
            child: Row(
              children: [
                Icon(HcIcons.forFacet(DeviceFacet.colorLight, on: on),
                    size: 19, color: colour),
                SizedBox(width: t.space.md),
                Expanded(
                  child: Text(widget.device.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: t.surface.onBase,
                      )),
                ),
                if (on) ...[
                  _Swatch(colour: _color),
                  SizedBox(width: t.space.sm),
                  Text('${_bri.round()}%',
                      style: TextStyle(
                          fontSize: 12,
                          color: t.surface.onBaseMuted,
                          fontFeatures: t.numericFontFeatures)),
                  SizedBox(width: t.space.sm),
                ],
                HomeEditButton(deviceId: widget.device.id),
                SizedBox(width: t.space.xs),
                _Toggle(
                  on: on,
                  onChanged: () =>
                      _notifier.command(widget.device.id, {'on': !on}),
                ),
              ],
            ),
          ),
        ),
        // The control.
        AnimatedSize(
          duration: t.motion.d(t.motion.base),
          curve: t.motion.curve,
          alignment: Alignment.topCenter,
          child: _open ? _panel(t) : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _panel(HcTokens t) {
    return Container(
      padding:
          EdgeInsets.fromLTRB(t.space.md, t.space.sm, t.space.md, t.space.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_color.withValues(alpha: 0.10), Colors.transparent],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Segmented(
            white: _white,
            onChanged: (w) => setState(() => _white = w),
          ),
          SizedBox(height: t.space.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 128,
                height: 128,
                child: _white
                    ? _TempBar(
                        temp: _temp,
                        onChanged: (v) => setState(() {
                          _dragging = true;
                          _temp = v;
                        }),
                        onEnd: () {
                          _dragging = false;
                          _commitTemp();
                        },
                      )
                    : _ColorWheel(
                        hue: _hue,
                        sat: _sat,
                        onChanged: (h, s) => setState(() {
                          _dragging = true;
                          _hue = h;
                          _sat = s;
                        }),
                        onEnd: () {
                          _dragging = false;
                          _commitColour();
                        },
                      ),
              ),
              SizedBox(width: t.space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('BRIGHTNESS',
                            style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w700,
                                color: t.surface.onBaseMuted)),
                        const Spacer(),
                        Text('${_bri.round()}%',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: t.surface.onBase,
                                fontFeatures: t.numericFontFeatures)),
                      ],
                    ),
                    SizedBox(height: t.space.sm),
                    _Slider(
                      value: _bri / 100,
                      trackColour: _color,
                      onChanged: (v) => setState(() {
                        _dragging = true;
                        _bri = (v * 100).clamp(1, 100);
                      }),
                      onEnd: () {
                        _dragging = false;
                        _commitBrightness();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: t.space.md),
          _Presets(onPick: (p) {
            setState(() {
              if (p.white != null) {
                _white = true;
                _temp = p.white!;
              } else {
                _white = false;
                _hue = p.hue!;
                _sat = p.sat!;
              }
            });
            _white ? _commitTemp() : _commitColour();
          }),
        ],
      ),
    );
  }
}

Color _whiteColor(double temp) {
  const cool = Color(0xFFBCD4FF),
      neutral = Color(0xFFFFF5EA),
      warm = Color(0xFFFFB26E);
  return temp < 50
      ? Color.lerp(cool, neutral, temp / 50)!
      : Color.lerp(neutral, warm, (temp - 50) / 50)!;
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.colour});
  final Color colour;
  @override
  Widget build(BuildContext context) => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: colour,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: colour.withValues(alpha: 0.6), blurRadius: 8)
          ],
        ),
      );
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.white, required this.onChanged});
  final bool white;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    Widget seg(String label, bool sel, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: t.space.md, vertical: t.space.xs + 1),
            decoration: BoxDecoration(
              color: sel ? t.surface.raised : Colors.transparent,
              borderRadius: t.radius.smR,
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: sel ? t.surface.onBase : t.surface.onBaseMuted)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface.base,
        borderRadius: t.radius.mdR,
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('Colour', !white, () => onChanged(false)),
        seg('White', white, () => onChanged(true)),
      ]),
    );
  }
}

/// The HSV wheel: hue around, saturation out from a white centre.
class _ColorWheel extends StatelessWidget {
  const _ColorWheel({
    required this.hue,
    required this.sat,
    required this.onChanged,
    required this.onEnd,
  });

  final double hue, sat;
  final void Function(double hue, double sat) onChanged;
  final VoidCallback onEnd;

  void _handle(Offset local, Size size) {
    final r = size.width / 2;
    final dx = local.dx - r, dy = local.dy - r;
    final h = (math.atan2(dy, dx) * 180 / math.pi + 360) % 360;
    final s = (math.sqrt(dx * dx + dy * dy) / r).clamp(0.0, 1.0);
    onChanged(h, s);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxWidth);
      final r = size.width / 2;
      final rad = hue * math.pi / 180;
      final hx = r + r * sat * math.cos(rad);
      final hy = r + r * sat * math.sin(rad);
      return GestureDetector(
        onPanDown: (d) => _handle(d.localPosition, size),
        onPanUpdate: (d) => _handle(d.localPosition, size),
        onPanEnd: (_) => onEnd(),
        child: CustomPaint(
          painter: _WheelPainter(),
          child: Stack(children: [
            Positioned(
              left: hx - 9,
              top: hy - 9,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: HSVColor.fromAHSV(1, hue, sat, 1).toColor(),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 3)
                  ],
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

class _WheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final rect = Rect.fromCircle(center: center, radius: r);
    final hue = Paint()
      ..shader = SweepGradient(
        colors: [
          for (var i = 0; i <= 360; i += 30)
            HSVColor.fromAHSV(1, (i % 360).toDouble(), 1, 1).toColor()
        ],
      ).createShader(rect);
    canvas.drawCircle(center, r, hue);
    final sat = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, Colors.white.withValues(alpha: 0)],
        stops: const [0, 0.9],
      ).createShader(rect);
    canvas.drawCircle(center, r, sat);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// The warm↔cool bar for white mode.
class _TempBar extends StatelessWidget {
  const _TempBar(
      {required this.temp, required this.onChanged, required this.onEnd});
  final double temp; // 0 cool .. 100 warm
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      void set(Offset p) =>
          onChanged((p.dy / c.maxHeight).clamp(0.0, 1.0) * 100);
      return GestureDetector(
        onPanDown: (d) => set(d.localPosition),
        onPanUpdate: (d) => set(d.localPosition),
        onPanEnd: (_) => onEnd(),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFBCD4FF), Color(0xFFFFF5EA), Color(0xFFFFB26E)],
            ),
          ),
          child: Stack(children: [
            Positioned(
              top: temp / 100 * c.maxHeight - 13,
              left: c.maxWidth / 2 - 13,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _whiteColor(temp),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 4)
                  ],
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.value,
    required this.trackColour,
    required this.onChanged,
    required this.onEnd,
  });
  final double value;
  final Color trackColour;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return LayoutBuilder(builder: (context, c) {
      void set(Offset p) => onChanged((p.dx / c.maxWidth).clamp(0.0, 1.0));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (d) => set(d.localPosition),
        onPanUpdate: (d) => set(d.localPosition),
        onPanEnd: (_) => onEnd(),
        child: SizedBox(
          height: 20,
          child: Center(
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                height: 10,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient:
                      LinearGradient(colors: [t.surface.sunken, trackColour]),
                ),
              ),
              Positioned(
                left: (value.clamp(0.0, 1.0) * c.maxWidth) - 9,
                top: -4,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: Colors.black45, blurRadius: 4)
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }
}

class _Preset {
  const _Preset.colour(this.hue, this.sat) : white = null;
  const _Preset.white(this.white)
      : hue = null,
        sat = null;
  final double? hue, sat, white;
}

const _presets = [
  _Preset.colour(0, 0.85),
  _Preset.colour(33, 0.9),
  _Preset.colour(120, 0.68),
  _Preset.colour(180, 0.7),
  _Preset.colour(210, 0.82),
  _Preset.colour(268, 0.74),
  _Preset.colour(320, 0.8),
  _Preset.white(15),
];

class _Presets extends StatelessWidget {
  const _Presets({required this.onPick});
  final ValueChanged<_Preset> onPick;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Wrap(
      spacing: t.space.sm,
      runSpacing: t.space.sm,
      children: [
        for (final p in _presets)
          GestureDetector(
            onTap: () => onPick(p),
            child: Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.white != null
                    ? _whiteColor(p.white!)
                    : HSVColor.fromAHSV(1, p.hue!, p.sat!, 1).toColor(),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
            ),
          ),
      ],
    );
  }
}

/// The compact switch (mirrors home_entity_row's).
class _Toggle extends StatelessWidget {
  const _Toggle({required this.on, required this.onChanged});
  final bool on;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    const h = 22.0;
    return GestureDetector(
      onTap: onChanged,
      child: AnimatedContainer(
        duration: t.motion.d(t.motion.fast),
        curve: t.motion.curve,
        width: h * 1.72,
        height: h,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: on ? t.accent.active : t.accent.inactive,
          borderRadius: BorderRadius.circular(t.radius.pill),
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
    );
  }
}
