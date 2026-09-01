/// A device reading, wired to a property of an element.
///
/// The app has bound data to a drawing for a while — `svg_bindings.dart` wires
/// an attribute to an attribute of an imported SVG, and solved the hard part
/// there: a number rarely arrives in the units the picture wants, so a binding
/// carries a range and maps one onto the other. What it could not do was reach
/// anything *else*. A card's tint, an icon's colour, a shape's angle were all
/// static, and the only way to make a drawing react was to bring your own SVG.
///
/// This is that same wire with the restriction lifted: any property of any
/// element, named by a string the element understands.
///
/// **One vocabulary, not a third.** The range fields are spelled as
/// `SvgBinding` spells them, and the "all four or none" rule is the same rule
/// for the same reason. `plugin_render.dart` uses the identical shape for a
/// plugin's portable widgets. A binding a person writes in one place reads the
/// same everywhere.
///
/// Pure and Flutter-free, so what a binding *means* is testable without a
/// widget tree.
library;

import '../models/device_state.dart';

/// What a resolved binding produced, or null for "no answer".
///
/// Null is a real and common outcome — the device is gone, the attribute has
/// never been sent, the value is not a number — and it always means *leave the
/// property as the author set it*. It never means zero. A gauge that fell to
/// nothing because a plugin restarted would be reporting on the house rather
/// than on itself.
typedef Bound = Object?;

class PropertyBinding {
  const PropertyBinding({
    required this.property,
    required this.deviceId,
    required this.key,
    this.inFrom,
    this.inTo,
    this.outFrom,
    this.outTo,
    this.decimals,
    this.map = const {},
    this.fallback,
  });

  /// The element property this drives — `color`, `rotation`, `opacity`,
  /// `width`, `content`. Named by the element rather than by an enum here, so
  /// a new element can offer a new property without this file changing.
  final String property;

  final String deviceId;

  /// Which reading on that device — `on`, `temperature`, `battery`.
  final String key;

  /// The reading's own range, mapped onto the property's. **All four or
  /// none**: a half-specified mapping is the case where a gauge quietly reads
  /// 0–1, which looks like a working card until somebody checks it against the
  /// house.
  final double? inFrom;
  final double? inTo;
  final double? outFrom;
  final double? outTo;

  final int? decimals;

  /// Value → look, for the readings that are not numbers.
  ///
  /// `{'true': 'accent', 'false': 'muted'}` is the common one. Keys are
  /// compared the way [DeviceState] actually reports things — a plugin sending
  /// the word `on` and one sending `true` mean the same thing, and a binding
  /// that matched only one would work in half the house.
  final Map<String, String> map;

  /// What to use when the map has no entry for the value. Null leaves the
  /// property alone, which is usually what an author means by not saying.
  final String? fallback;

  bool get hasRange =>
      inFrom != null && inTo != null && outFrom != null && outTo != null;

  bool get isLookup => map.isNotEmpty;

  static PropertyBinding? fromJson(Object? json) {
    if (json is! Map) return null;
    final property = json['property'];
    final deviceId = json['device_id'];
    final key = json['key'];
    if (property is! String || deviceId is! String || key is! String) {
      return null;
    }
    if (property.isEmpty || deviceId.isEmpty || key.isEmpty) return null;

    return PropertyBinding(
      property: property,
      deviceId: deviceId,
      key: key,
      inFrom: _finite(json['in_from']),
      inTo: _finite(json['in_to']),
      outFrom: _finite(json['out_from']),
      outTo: _finite(json['out_to']),
      decimals:
          json['decimals'] is num ? (json['decimals'] as num).toInt() : null,
      map: {
        for (final e in (json['map'] as Map? ?? const {}).entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      },
      fallback: json['fallback'] is String ? json['fallback'] as String : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'property': property,
        'device_id': deviceId,
        'key': key,
        if (hasRange) ...{
          'in_from': inFrom,
          'in_to': inTo,
          'out_from': outFrom,
          'out_to': outTo,
        },
        if (decimals != null) 'decimals': decimals,
        if (map.isNotEmpty) 'map': map,
        if (fallback != null) 'fallback': fallback,
      };

  PropertyBinding copyWith({
    String? property,
    String? deviceId,
    String? key,
    Object? inFrom = _keep,
    Object? inTo = _keep,
    Object? outFrom = _keep,
    Object? outTo = _keep,
    Map<String, String>? map,
    Object? fallback = _keep,
  }) =>
      PropertyBinding(
        property: property ?? this.property,
        deviceId: deviceId ?? this.deviceId,
        key: key ?? this.key,
        inFrom: identical(inFrom, _keep) ? this.inFrom : inFrom as double?,
        inTo: identical(inTo, _keep) ? this.inTo : inTo as double?,
        outFrom: identical(outFrom, _keep) ? this.outFrom : outFrom as double?,
        outTo: identical(outTo, _keep) ? this.outTo : outTo as double?,
        decimals: decimals,
        map: map ?? this.map,
        fallback:
            identical(fallback, _keep) ? this.fallback : fallback as String?,
      );

  /// What this binding says the property should be, for the house as [lookup]
  /// describes it.
  ///
  /// Returns a `double` for a range binding, a `String` for a lookup, and null
  /// when there is no answer.
  Bound resolve(DeviceState? Function(String id) lookup) {
    final device = lookup(deviceId);
    if (device == null) return null;
    final raw = device.state[key];
    if (raw == null) return null;

    if (isLookup) return map[_canonical(raw)] ?? fallback;

    final n = _asNumber(raw);
    if (n == null) return null;
    if (!hasRange) return n;

    final span = inTo! - inFrom!;
    // A zero-width input range divides nothing. The bottom of the output is the
    // honest answer — every input is equally the minimum — where a division
    // would answer infinity and paint a full bar.
    if (span == 0) return outFrom;
    return outFrom! + ((n - inFrom!) / span) * (outTo! - outFrom!);
  }

  /// How a value is spelled when looking it up in [map].
  ///
  /// `true`, `"true"` and `"on"` are one key. One plugin sends a bool and
  /// another sends the word, and an author should not have to write both.
  static String _canonical(Object raw) {
    if (raw is bool) return raw ? 'true' : 'false';
    final s = raw.toString().toLowerCase();
    return switch (s) {
      'on' || 'yes' || '1' => 'true',
      'off' || 'no' || '0' => 'false',
      _ => s,
    };
  }

  static double? _asNumber(Object? raw) {
    if (raw is num) return raw.isFinite ? raw.toDouble() : null;
    // A plugin sending "21.5" for a temperature is common enough that refusing
    // it would make the feature look broken on real houses.
    if (raw is String) return double.tryParse(raw);
    if (raw is bool) return raw ? 1 : 0;
    return null;
  }

  static double? _finite(Object? raw) {
    if (raw is! num) return null;
    final v = raw.toDouble();
    return v.isFinite ? v : null;
  }
}

const Object _keep = Object();

/// Every binding on an element, and the one place they are read from a config.
///
/// Stored under `bindings` beside the element's own settings, the same space
/// `style` and `layer` already ride in. A field not understood by a reader is
/// left alone rather than dropped, which is what lets a page written by a newer
/// client keep working here.
class Bindings {
  const Bindings(this.all);

  final List<PropertyBinding> all;

  static const empty = Bindings([]);

  static Bindings fromConfig(Map<String, dynamic> config) => Bindings([
        for (final b in (config['bindings'] as List? ?? const []))
          if (PropertyBinding.fromJson(b) case final binding?) binding,
      ]);

  /// [config] with these bindings applied.
  ///
  /// Writes nothing when there are none, so an element nobody has wired leaves
  /// the document byte-identical — the rule every other optional thing in this
  /// codebase follows.
  Map<String, dynamic> toConfig(Map<String, dynamic> config) {
    final next = {...config};
    if (all.isEmpty) {
      next.remove('bindings');
    } else {
      next['bindings'] = [for (final b in all) b.toJson()];
    }
    return next;
  }

  PropertyBinding? forProperty(String property) => all
      .where((b) => b.property == property)
      .cast<PropertyBinding?>()
      .firstOrNull;

  /// The resolved value for [property], or null to leave it as authored.
  Bound resolve(String property, DeviceState? Function(String id) lookup) =>
      forProperty(property)?.resolve(lookup);

  Bindings without(String property) => Bindings([
        for (final b in all)
          if (b.property != property) b
      ]);

  Bindings with_(PropertyBinding binding) => Bindings([
        for (final b in all)
          if (b.property != binding.property) b,
        binding,
      ]);
}
