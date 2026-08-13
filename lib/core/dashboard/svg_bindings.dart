/// A drawing you made, wired to the house.
///
/// Tier 2 of the element model. Tier 1 draws instruments we know how to draw;
/// tier 3 runs code you wrote. This is the middle, and it is the one most
/// people actually want: **you already have the artwork** — from Figma, from
/// Inkscape, from a floor-plan export — and what is missing is not a renderer
/// but a way to say *this arc is the speed and that text is the number*.
///
/// **It is tier 3 with the code written for you.** The bindings compile to a
/// short script that runs beside the drawing inside the same sandbox the code
/// element uses: the same iframe with no same-origin, the same
/// `default-src 'none'`, the same nonce, the same device grant. That is a
/// deliberate refusal to invent a second security model — and it is also what
/// makes the fidelity right, because the browser draws the SVG rather than a
/// renderer that silently ignores filters.
///
/// The alternative was to inject the SVG into our own document and mutate it by
/// id. That is faster and it is a cross-site scripting hole: `innerHTML` will
/// not run a `<script>` tag, but SVG carries `onload` and friends that run
/// perfectly well, and the drawing is a file someone downloaded.
///
/// Pure and Flutter-free, so what a binding *means* is testable without a
/// browser.
library;

import 'dart:convert';

/// One wire: an element in the drawing, an attribute on it, and where the value
/// comes from.
class SvgBinding {
  const SvgBinding({
    required this.elementId,
    required this.attribute,
    required this.deviceId,
    required this.key,
    this.inFrom,
    this.inTo,
    this.outFrom,
    this.outTo,
    this.decimals,
  });

  /// The `id` in the drawing. Not a selector: a selector is a small language,
  /// and every id in the file is already listed for you by [svgElementIds].
  final String elementId;

  /// The attribute to set, or [textAttribute] for the element's content.
  ///
  /// A plain attribute rather than a style property, because the two are not
  /// the same thing in SVG and offering both without saying which wins would
  /// produce a binding that silently does nothing.
  final String attribute;

  final String deviceId;

  /// Which reading on that device — `speed`, `temperature`, `on`.
  final String key;

  /// The value's own range, mapped onto the attribute's. All four or none:
  /// a half-specified mapping is the case where a gauge quietly reads 0–1
  /// instead of 0–4, and it is better refused than guessed.
  final double? inFrom;
  final double? inTo;
  final double? outFrom;
  final double? outTo;

  /// For [textAttribute]. Null trims trailing zeros.
  final int? decimals;

  /// The attribute name that means "the text inside this element".
  static const textAttribute = 'text';

  bool get isText => attribute == textAttribute;

  bool get hasRange =>
      inFrom != null && inTo != null && outFrom != null && outTo != null;

  /// True when this binding can do anything at all. A row half-filled in the
  /// editor is not an error to shout about — it is a row you have not finished
  /// — but it must not reach the drawing.
  bool get isComplete =>
      elementId.isNotEmpty &&
      attribute.isNotEmpty &&
      deviceId.isNotEmpty &&
      key.isNotEmpty;

  static SvgBinding fromJson(Map<String, dynamic> json) => SvgBinding(
        elementId: '${json['id'] ?? ''}',
        attribute: '${json['attr'] ?? ''}',
        deviceId: '${json['device'] ?? ''}',
        key: '${json['key'] ?? ''}',
        inFrom: _num(json['from']),
        inTo: _num(json['to']),
        outFrom: _num(json['out_from']),
        outTo: _num(json['out_to']),
        decimals: json['decimals'] is num
            ? (json['decimals'] as num).toInt().clamp(0, 6)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': elementId,
        'attr': attribute,
        'device': deviceId,
        'key': key,
        if (inFrom != null) 'from': inFrom,
        if (inTo != null) 'to': inTo,
        if (outFrom != null) 'out_from': outFrom,
        if (outTo != null) 'out_to': outTo,
        if (decimals != null) 'decimals': decimals,
      };

  SvgBinding copyWith({
    String? elementId,
    String? attribute,
    String? deviceId,
    String? key,
    Object? inFrom = _keep,
    Object? inTo = _keep,
    Object? outFrom = _keep,
    Object? outTo = _keep,
    Object? decimals = _keep,
  }) =>
      SvgBinding(
        elementId: elementId ?? this.elementId,
        attribute: attribute ?? this.attribute,
        deviceId: deviceId ?? this.deviceId,
        key: key ?? this.key,
        inFrom: _number(inFrom, this.inFrom),
        inTo: _number(inTo, this.inTo),
        outFrom: _number(outFrom, this.outFrom),
        outTo: _number(outTo, this.outTo),
        decimals: identical(decimals, _keep)
            ? this.decimals
            : (decimals as num?)?.toInt(),
      );

  static double? _num(Object? raw) => raw is num ? raw.toDouble() : null;

  /// Resolves one of [copyWith]'s sentinel parameters.
  ///
  /// **Coerced, never cast.** The sentinel forces these parameters to be
  /// `Object?`, which throws away the static check that would have caught a
  /// caller passing `10` where `10.0` was meant — and `as double?` then throws
  /// at runtime, inside a field's `onChanged`, where the exception aborts the
  /// write and leaves the control showing a value the document never received.
  /// A silent no-op is the worst failure this editor can have, so a number is
  /// taken as a number.
  static double? _number(Object? raw, double? current) {
    if (identical(raw, _keep)) return current;
    return raw is num ? raw.toDouble() : null;
  }
}

const Object _keep = Object();

/// Where the two keys live inside `config`.
const svgSourceKey = 'svg';
const svgBindingsKey = 'bindings';

List<SvgBinding> bindingsFromConfig(Map<String, dynamic> config) => [
      for (final raw in (config[svgBindingsKey] as List?) ?? const [])
        if (raw is Map) SvgBinding.fromJson(Map<String, dynamic>.from(raw)),
    ];

Map<String, dynamic> bindingsToConfig(
  Map<String, dynamic> config,
  List<SvgBinding> bindings,
) {
  final next = {...config};
  if (bindings.isEmpty) {
    next.remove(svgBindingsKey);
  } else {
    next[svgBindingsKey] = [for (final b in bindings) b.toJson()];
  }
  return next;
}

/// Every `id` in the drawing, in the order they appear.
///
/// A regex rather than an XML parse, and the distinction matters: this is a
/// *listing aid* for a dropdown, not a validator. Offering an id that turns out
/// not to exist costs a binding that does nothing and says so in the console;
/// pulling in an XML parser to be certain would cost a dependency for a hint.
///
/// Ordered as written rather than alphabetically, because a drawing's ids come
/// out in the order the artwork was built and that is the order the author
/// remembers them in.
List<String> svgElementIds(String source) {
  final ids = <String>[];
  final pattern = RegExp('''id\\s*=\\s*["']([^"']+)["']''');
  for (final match in pattern.allMatches(source)) {
    final id = match.group(1)!.trim();
    if (id.isNotEmpty && !ids.contains(id)) ids.add(id);
  }
  return ids;
}

/// The attributes worth offering for a numeric binding, per the shapes people
/// actually animate. Free text is still allowed — SVG has hundreds and this is
/// a shortlist, not a whitelist.
const svgCommonAttributes = <String>[
  'stroke-dashoffset',
  'stroke-dasharray',
  'stroke-width',
  'opacity',
  'r',
  'width',
  'height',
  'x',
  'y',
  'cx',
  'cy',
];

/// A value moved from its own range onto the attribute's.
///
/// Clamped at both ends: an arc whose offset runs past its dash array draws a
/// second lap, and a temperature above the top of a scale should read as full
/// rather than as wrapped.
double mapValue(
    double value, double inFrom, double inTo, double outFrom, double outTo) {
  final span = inTo - inFrom;
  if (span == 0) return outFrom;
  final t = ((value - inFrom) / span).clamp(0.0, 1.0);
  return outFrom + (outTo - outFrom) * t;
}

/// The script that applies [bindings], to run beside the drawing.
///
/// Generated rather than hand-written per card, and deliberately dull: it reads
/// the same `homecore.onUpdate` feed a code element gets, so a person who
/// outgrows the binding editor can open the same drawing as a code element and
/// find nothing surprising.
String buildBinderScript(List<SvgBinding> bindings) {
  final usable = [
    for (final b in bindings)
      if (b.isComplete) b.toJson(),
  ];
  return '''
<script>
(function () {
  var BINDINGS = ${jsonEncode(usable)};

  function trim(v) {
    var s = Number(v).toFixed(1);
    return s.slice(-2) === '.0' ? s.slice(0, -2) : s;
  }

  homecore.onUpdate(function (states) {
    for (var i = 0; i < BINDINGS.length; i++) {
      var b = BINDINGS[i];
      var device = states[b.device];
      if (!device) { homecore.log('No device for #' + b.id); continue; }

      var raw = device.state[b.key];
      var el = document.getElementById(b.id);
      if (!el) { homecore.log('No element #' + b.id + ' in this drawing'); continue; }

      if (b.attr === 'text') {
        el.textContent = raw === undefined || raw === null
          ? '--'
          : (typeof raw === 'number'
              ? (b.decimals === undefined ? trim(raw) : raw.toFixed(b.decimals))
              : String(raw));
        continue;
      }

      var value = Number(raw);
      if (!isFinite(value)) { homecore.log('#' + b.id + ': ' + b.key + ' is not a number'); continue; }

      if (b.from !== undefined && b.to !== undefined &&
          b.out_from !== undefined && b.out_to !== undefined) {
        var span = b.to - b.from;
        var t = span === 0 ? 0 : (value - b.from) / span;
        t = t < 0 ? 0 : (t > 1 ? 1 : t);
        value = b.out_from + (b.out_to - b.out_from) * t;
      }
      el.setAttribute(b.attr, String(value));
    }
  });
})();
</script>
''';
}

/// The drawing and its binder, as the body of a sandboxed document.
///
/// The SVG goes in verbatim. It is not sanitised and does not need to be: it is
/// about to be handed to a frame with an opaque origin, no network and no
/// access to this app — which is exactly the containment that makes "paste a
/// file you downloaded" a safe thing to offer.
String buildSvgBody(String source, List<SvgBinding> bindings) =>
    '$source\n${buildBinderScript(bindings)}';

/// What a new SVG element starts life as.
///
/// A drawing rather than an empty box, and one whose ids are obviously
/// bindable: the first question this element raises is "what do I bind to?",
/// and a starter that already has `#dial` and `#readout` in it answers that
/// before anyone opens the documentation.
const svgStarter = '''
<svg viewBox="0 0 200 120" width="100%" height="100%">
  <circle cx="100" cy="70" r="46" fill="none" stroke="var(--hc-line)"
          stroke-width="10" stroke-dasharray="217" stroke-dashoffset="54"
          transform="rotate(135 100 70)" stroke-linecap="round"/>
  <circle id="dial" cx="100" cy="70" r="46" fill="none" stroke="var(--hc-accent)"
          stroke-width="10" stroke-dasharray="217" stroke-dashoffset="217"
          transform="rotate(135 100 70)" stroke-linecap="round"/>
  <text id="readout" x="100" y="76" font-size="26" fill="var(--hc-ink)"
        text-anchor="middle" font-family="system-ui">--</text>
</svg>
''';
