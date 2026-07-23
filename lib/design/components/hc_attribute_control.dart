import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/schema/device_schema.dart';
import '../tokens.dart';
import 'hc_dialog.dart';
import 'hc_surface.dart';

/// Renders the right control for one device attribute, from its schema.
///
/// This is the extensibility payoff, and it needs **no core changes and no
/// plugin-specific code**: a plugin that registers a schema gets correct
/// controls here for free, including attributes nobody in this repo has heard
/// of.
///
/// Two realities keep it honest:
///
/// * **Most devices have no schema.** On a real install, 9 of 168 do. So
///   [heuristicSchemaFor] infers one from the attribute's name and value shape,
///   and everything below runs on that instead.
/// * **`writable: false` means display-only.** A read-only attribute rendered as
///   a slider is a lie the user discovers by dragging it.
class HcAttributeControl extends StatelessWidget {
  const HcAttributeControl({
    super.key,
    required this.name,
    required this.schema,
    required this.value,
    this.onCommit,
    this.enabled = true,
  });

  final String name;
  final AttributeSchema schema;

  /// The current reported value, or null. A schema attribute may legitimately
  /// have no value: Hue exposes a writable `color_temp` in Kelvin while only
  /// *reporting* `color_temp_mirek`.
  final Object? value;

  /// Sends the command. Null makes the control read-only.
  final void Function(Object value)? onCommit;

  final bool enabled;

  bool get _live => enabled && schema.writable && onCommit != null;

  String get _label => schema.displayName ?? _humanize(name);

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: schema.writable
                            ? t.surface.onBase
                            : t.surface.onBaseMuted,
                      ),
                ),
              ),
              if (!schema.writable)
                Tooltip(
                  message: 'Reported by the device — not settable',
                  child: Icon(Icons.lock_outline,
                      size: 12, color: t.surface.onBaseMuted),
                ),
            ],
          ),
          SizedBox(height: t.space.xs),
          _control(context, t),
        ],
      ),
    );
  }

  Widget _control(BuildContext context, HcTokens t) {
    if (!schema.writable) return _readonly(context, t);

    final control = switch (schema.kind) {
      AttributeKind.bool_ => _boolControl(t),
      AttributeKind.enum_ => _enumControl(context),
      AttributeKind.integer ||
      AttributeKind.float ||
      AttributeKind.colorTemp =>
        schema.hasRange ? _slider(context, t) : _numberField(context),
      AttributeKind.string => _textField(context),
      AttributeKind.colorXy ||
      AttributeKind.colorRgb =>
        _colorControl(context, t),
      AttributeKind.json => _readonly(context, t),
    };

    // Studio control styling: amber, not Material blue. A gradient (colour-temp)
    // slider keeps its own transparent track — the gradient is the label — but
    // inherits the amber thumb from here.
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: t.accent.active,
        inactiveTrackColor: t.surface.overlay,
        thumbColor: t.accent.active,
        overlayColor: t.accent.active.withValues(alpha: 0.14),
        trackHeight: 5,
      ),
      child: control,
    );
  }

  // -- controls ------------------------------------------------------------

  Widget _boolControl(HcTokens t) => Align(
        alignment: Alignment.centerLeft,
        child: Switch(
          value: value == true,
          onChanged: _live ? (v) => onCommit!(v) : null,
          activeThumbColor: t.accent.active,
          activeTrackColor: t.accent.active.withValues(alpha: 0.35),
          inactiveThumbColor: t.surface.onBaseMuted,
          inactiveTrackColor: t.surface.overlay,
        ),
      );

  Widget _slider(BuildContext context, HcTokens t) {
    final min = schema.min!;
    final max = schema.max!;
    final current = (_asDouble(value) ?? min).clamp(min, max);

    // A colour-temperature slider should look like colour temperature — the
    // gradient is the label.
    final gradient = schema.kind == AttributeKind.colorTemp
        ? const LinearGradient(
            colors: [Color(0xFFFFB871), Color(0xFFFFF3E4), Color(0xFFCFE4FF)],
          )
        : null;

    return Row(
      children: [
        Expanded(
          child: _GradientSlider(
            value: current,
            min: min,
            max: max,
            // Without divisions the slider would pretend to a precision the
            // device does not have: Hue's colour temp steps in 100K.
            divisions: schema.step != null && schema.step! > 0
                ? ((max - min) / schema.step!).round().clamp(1, 1000)
                : null,
            gradient: gradient,
            onChanged: _live ? (v) => onCommit!(_coerce(v)) : null,
          ),
        ),
        SizedBox(width: t.space.sm),
        SizedBox(
          width: 64,
          child: HcValue(_format(current), unit: schema.unit, muted: !_live),
        ),
      ],
    );
  }

  Widget _enumControl(BuildContext context) {
    final options = schema.options ?? const <String>[];
    if (options.isEmpty) return _textField(context);

    // A few options are faster to hit as chips than as a dropdown — and on a
    // wall panel a dropdown is a hostile control.
    if (options.length <= 4) {
      return Wrap(
        spacing: 6,
        children: [
          for (final o in options)
            ChoiceChip(
              label: Text(_humanize(o)),
              selected: value == o,
              onSelected: _live ? (_) => onCommit!(o) : null,
            ),
        ],
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: options.contains(value) ? value as String : null,
      isExpanded: true,
      decoration:
          const InputDecoration(isDense: true, border: OutlineInputBorder()),
      items: [
        for (final o in options)
          DropdownMenuItem(value: o, child: Text(_humanize(o))),
      ],
      onChanged: _live ? (v) => v == null ? null : onCommit!(v) : null,
    );
  }

  Widget _numberField(BuildContext context) => TextFormField(
        initialValue: value?.toString() ?? '',
        enabled: _live,
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          suffixText: schema.unit,
        ),
        keyboardType: TextInputType.number,
        onFieldSubmitted: (v) {
          final n = num.tryParse(v);
          if (n != null) onCommit?.call(_coerce(n.toDouble()));
        },
      );

  Widget _textField(BuildContext context) => TextFormField(
        initialValue: value?.toString() ?? '',
        enabled: _live,
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          suffixText: schema.unit,
        ),
        onFieldSubmitted: (v) => onCommit?.call(v),
      );

  Widget _colorControl(BuildContext context, HcTokens t) {
    final swatch = _currentColor() ?? t.accent.inactive;

    return Row(
      children: [
        GestureDetector(
          onTap: _live ? () => _pickColor(context) : null,
          child: Container(
            width: t.density.controlHeight,
            height: t.density.controlHeight,
            decoration: BoxDecoration(
              color: swatch,
              shape: BoxShape.circle,
              border: Border.all(color: t.stroke.hairline),
            ),
          ),
        ),
        SizedBox(width: t.space.sm),
        if (_live)
          TextButton(
            onPressed: () => _pickColor(context),
            style: TextButton.styleFrom(foregroundColor: t.accent.active),
            child: const Text('Change'),
          ),
      ],
    );
  }

  Future<void> _pickColor(BuildContext context) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _ColorPicker(initial: _currentColor()),
    );
    if (picked == null) return;

    // Emit the shape core declared, not one of our choosing:
    //   color_rgb → {r, g, b} 0–255
    //   color_xy  → {x, y} CIE 1931
    onCommit?.call(
      schema.kind == AttributeKind.colorRgb
          ? {
              'r': (picked.r * 255).round(),
              'g': (picked.g * 255).round(),
              'b': (picked.b * 255).round(),
            }
          : () {
              final (x, y) = rgbToXy(picked);
              return {'x': x, 'y': y};
            }(),
    );
  }

  Widget _readonly(BuildContext context, HcTokens t) {
    final text = switch (value) {
      null => '—',
      Map() || List() => const JsonEncoder.withIndent('  ').convert(value),
      _ => '$value',
    };

    if (!text.contains('\n')) {
      return HcValue(text, unit: schema.unit, muted: true);
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(t.space.sm),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: t.radius.smR,
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: t.surface.onBaseMuted,
        ),
      ),
    );
  }

  // -- helpers -------------------------------------------------------------

  /// Integers must go out as integers. Sending `brightness_pct: 55.0` where the
  /// schema says `integer` invites a plugin-side type error.
  Object _coerce(double v) =>
      schema.kind == AttributeKind.float ? v : v.round();

  String _format(double v) =>
      schema.kind == AttributeKind.float && (schema.step ?? 1) < 1
          ? v.toStringAsFixed(1)
          : v.round().toString();

  Color? _currentColor() {
    final v = value;
    if (v is! Map) return null;
    if (v['r'] case final num r) {
      return Color.fromARGB(
        255,
        r.toInt(),
        (v['g'] as num?)?.toInt() ?? 0,
        (v['b'] as num?)?.toInt() ?? 0,
      );
    }
    if (v['x'] case final num x) {
      return xyToRgb(x.toDouble(), (v['y'] as num?)?.toDouble() ?? 0);
    }
    return null;
  }
}

/// A slider that can paint a gradient behind itself, so a colour-temp control
/// looks like what it does.
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.gradient,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final Gradient? gradient;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final slider = Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      onChanged: onChanged,
    );

    if (gradient == null) return slider;

    return Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: Colors.transparent,
          ),
          child: slider,
        ),
      ],
    );
  }
}

class _ColorPicker extends StatefulWidget {
  const _ColorPicker({this.initial});

  final Color? initial;

  @override
  State<_ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  late HSVColor _hsv =
      HSVColor.fromColor(widget.initial ?? const Color(0xFFFFB661));

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final color = _hsv.withValue(1).withAlpha(1).toColor();
    final pure = HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor();

    return HcDialog(
      title: 'Colour',
      actions: [
        HcButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        HcButton(
            label: 'Apply',
            kind: HcButtonKind.primary,
            onPressed: () => Navigator.pop(context, color)),
      ],
      child: SizedBox(
        width: 300,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbColor: Colors.white,
            overlayColor: Colors.white.withValues(alpha: 0.12),
            trackHeight: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A living preview that glows its own colour.
              Container(
                height: 64,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: color.withValues(alpha: 0.55),
                        blurRadius: 18,
                        spreadRadius: -2),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _row(t, 'Hue', () {
                return _GradientSlider(
                  value: _hsv.hue,
                  min: 0,
                  max: 360,
                  gradient: const LinearGradient(colors: [
                    Color(0xFFFF0000),
                    Color(0xFFFFFF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FFFF),
                    Color(0xFF0000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0000),
                  ]),
                  onChanged: (v) => setState(() => _hsv = _hsv.withHue(v)),
                );
              }()),
              _row(t, 'Saturation', () {
                return _GradientSlider(
                  value: _hsv.saturation,
                  min: 0,
                  max: 1,
                  gradient:
                      LinearGradient(colors: [const Color(0xFFBFC7D2), pure]),
                  onChanged: (v) =>
                      setState(() => _hsv = _hsv.withSaturation(v)),
                );
              }()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(HcTokens t, String label, Widget child) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
                width: 84,
                child: Text(label,
                    style:
                        TextStyle(fontSize: 13, color: t.surface.onBaseMuted))),
            Expanded(child: child),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Heuristic fallback — the path most devices actually take
// ---------------------------------------------------------------------------

/// Attributes that are plainly metadata, never controls.
const _metadataAttributes = {
  'kind',
  'bridge_id',
  'resource_id',
  'plugin_id',
  'last_seen',
  'effect_values',
};

/// Bool attributes that really are commands. Everything else that reports a
/// bool — `motion`, `open`, `low_battery` — is a *reading*, and rendering a
/// switch for it would invite the user to "turn off" a motion sensor.
const _writableBools = {'on', 'locked', 'muted', 'enabled', 'activate'};

/// Infers a schema for a device that never registered one.
///
/// This is not a safety net; it is the common case. It reads the attribute's
/// **name** as well as its value, because a bare 0–255 integer is a brightness
/// on a light and a meaningless number anywhere else.
///
/// Anything it cannot place becomes read-only: guessing that an unknown value is
/// writable risks firing a command the device never advertised.
AttributeSchema heuristicSchemaFor(String name, Object? value) {
  if (_metadataAttributes.contains(name) || name.startsWith('supports_')) {
    return const AttributeSchema(kind: AttributeKind.json, writable: false);
  }

  return switch (value) {
    bool _ => AttributeSchema(
        kind: AttributeKind.bool_,
        writable: _writableBools.contains(name),
      ),
    num n => _numeric(name, n),
    String _ => const AttributeSchema(
        kind: AttributeKind.string,
        writable: false,
      ),
    Map m when m.containsKey('x') && m.containsKey('y') =>
      const AttributeSchema(kind: AttributeKind.colorXy),
    Map m when m.containsKey('r') && m.containsKey('g') =>
      const AttributeSchema(kind: AttributeKind.colorRgb),
    _ => const AttributeSchema(kind: AttributeKind.json, writable: false),
  };
}

AttributeSchema _numeric(String name, num value) => switch (name) {
      'brightness_pct' => const AttributeSchema(
          kind: AttributeKind.integer,
          displayName: 'Brightness',
          unit: '%',
          min: 1,
          max: 100,
          step: 1,
        ),
      'brightness' => const AttributeSchema(
          kind: AttributeKind.integer,
          displayName: 'Brightness',
          min: 0,
          max: 255,
          step: 1,
        ),
      'position' => const AttributeSchema(
          kind: AttributeKind.integer,
          displayName: 'Position',
          unit: '%',
          min: 0,
          max: 100,
          step: 1,
        ),
      'volume' => const AttributeSchema(
          kind: AttributeKind.integer,
          displayName: 'Volume',
          unit: '%',
          min: 0,
          max: 100,
          step: 1,
        ),
      'color_temp' => const AttributeSchema(
          kind: AttributeKind.colorTemp,
          displayName: 'Colour temperature',
          unit: 'K',
          min: 2000,
          max: 6500,
          step: 100,
        ),
      'temperature' => const AttributeSchema(
          kind: AttributeKind.float,
          displayName: 'Temperature',
          unit: '°',
          writable: false,
        ),
      'humidity' => const AttributeSchema(
          kind: AttributeKind.integer,
          displayName: 'Humidity',
          unit: '%',
          writable: false,
        ),
      'battery' => const AttributeSchema(
          kind: AttributeKind.integer,
          displayName: 'Battery',
          unit: '%',
          writable: false,
        ),
      // An unrecognised number is a reading, not a dial.
      _ => AttributeSchema(
          kind: value is int ? AttributeKind.integer : AttributeKind.float,
          writable: false,
        ),
    };

/// The schema to render a device's attribute with: the registered one when it
/// exists, an inferred one otherwise.
AttributeSchema schemaFor(
  String name,
  Object? value,
  DeviceSchema? deviceSchema,
) =>
    deviceSchema?[name] ?? heuristicSchemaFor(name, value);

// ---------------------------------------------------------------------------
// Colour conversion
// ---------------------------------------------------------------------------

/// CIE 1931 xy → sRGB, for showing a swatch.
///
/// Uses the sRGB/D65 matrix, which is the exact inverse of the one [rgbToXy]
/// uses. Pairing Hue's Wide-RGB matrix with sRGB's — an easy mistake, since both
/// are published as "the" conversion — makes the round trip drift by ~0.07 in x,
/// which is a visibly different colour.
Color xyToRgb(double x, double y) {
  if (y <= 0) return const Color(0xFF000000);

  const luminance = 1.0;
  final z = 1.0 - x - y;
  final bigX = (luminance / y) * x;
  final bigZ = (luminance / y) * z;

  var r = bigX * 3.2406 - luminance * 1.5372 - bigZ * 0.4986;
  var g = -bigX * 0.9689 + luminance * 1.8758 + bigZ * 0.0415;
  var b = bigX * 0.0557 - luminance * 0.2040 + bigZ * 1.0570;

  // Normalise before gamma: an out-of-gamut xy can exceed 1 in a channel, and
  // clamping first would shift the hue rather than just its brightness.
  final peak = [r, g, b].reduce(math.max);
  if (peak > 1) {
    r /= peak;
    g /= peak;
    b /= peak;
  }

  double gamma(double c) {
    final v = c.clamp(0.0, 1.0);
    return v <= 0.0031308
        ? 12.92 * v
        : 1.055 * math.pow(v, 1 / 2.4).toDouble() - 0.055;
  }

  return Color.fromARGB(
    255,
    (gamma(r) * 255).round(),
    (gamma(g) * 255).round(),
    (gamma(b) * 255).round(),
  );
}

/// sRGB → CIE 1931 xy, rounded to the 4 decimals Hue actually uses.
(double, double) rgbToXy(Color c) {
  double linear(double v) =>
      v > 0.04045 ? math.pow((v + 0.055) / 1.055, 2.4).toDouble() : v / 12.92;

  final r = linear(c.r);
  final g = linear(c.g);
  final b = linear(c.b);

  final x = r * 0.4124 + g * 0.3576 + b * 0.1805;
  final y = r * 0.2126 + g * 0.7152 + b * 0.0722;
  final z = r * 0.0193 + g * 0.1192 + b * 0.9505;

  final sum = x + y + z;
  if (sum == 0) return (0.0, 0.0);

  return (
    double.parse((x / sum).toStringAsFixed(4)),
    double.parse((y / sum).toStringAsFixed(4)),
  );
}

String _humanize(String raw) {
  if (raw.isEmpty) return raw;
  final s = raw.replaceAll('_', ' ');
  return s[0].toUpperCase() + s.substring(1);
}

double? _asDouble(Object? v) => v is num ? v.toDouble() : null;
