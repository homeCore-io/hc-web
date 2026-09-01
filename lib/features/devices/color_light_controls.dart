import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/devices/color_space.dart' show rgbToXy;
import '../../design/components/colour_controls.dart';
import '../../design/tokens.dart';

/// The real control for a colour / tunable-white bulb: a colour wheel, a
/// warm↔cool temperature bar, brightness and presets.
///
/// A colour bulb is the device a bare toggle most obviously fails — its whole
/// point is the light it makes. This used to unfold *inside* the room card,
/// which made it the one device on the house that answered somewhere other than
/// the panel; every other row opens the drawer. It is the panel's hero now, and
/// the room shows a plain row like everything else.
class ColorLightControls extends ConsumerStatefulWidget {
  const ColorLightControls({super.key, required this.device});

  final DeviceState device;

  @override
  ConsumerState<ColorLightControls> createState() => _ColorLightControlsState();
}

// Tunable-white range, Kelvin. Warm end first.
// Named in colour_controls.dart now, so the panel and any drawn warmth control
// agree on where warm and cool are.
const _kWarm = kWarmKelvin, _kCool = kCoolKelvin;

class _ColorLightControlsState extends ConsumerState<ColorLightControls> {
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
  void didUpdateWidget(covariant ColorLightControls old) {
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
      ? whiteColour(_temp)
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
  Widget build(BuildContext context) => _panel(HcTokens.of(context));

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
                    ? WarmthBar(
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
                    : ColourWheel(
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
                            style: t.text.overlineStyle.copyWith(
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w700,
                                color: t.surface.onBaseMuted)),
                        const Spacer(),
                        Text('${_bri.round()}%',
                            style: t.text.bodySmallStyle.copyWith(
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
                style: t.text.captionStyle.copyWith(
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
                  borderRadius: t.radius.xsR,
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
                    ? whiteColour(p.white!)
                    : HSVColor.fromAHSV(1, p.hue!, p.sat!, 1).toColor(),
                border: Border.all(color: t.stroke.hairline),
              ),
            ),
          ),
      ],
    );
  }
}
