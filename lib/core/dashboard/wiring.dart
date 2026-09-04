/// Every wire on a page, gathered from what the document already says.
///
/// **A properties panel shows one binding at a time and hides the rest.** A
/// page with forty of them is a page nobody can audit: to find out why the
/// kitchen icon is the wrong colour you have to select each element in turn and
/// read its Data section, and to find out what a device drives you cannot ask
/// at all. This is the same data, gathered.
///
/// **A view, not a format.** Nothing here is stored. Every wire is derived from
/// bindings and `on_tap` actions that already live in the config, so the wiring
/// view adds no key to any document and there is nothing for a client that has
/// never heard of it to fail to read. That is the whole of what the graph idea
/// is worth borrowing — the wire, not the runtime.
///
/// **It is not an automation editor.** Wiring a page is about what is *drawn*.
/// When the boiler should actually fire is a rule, and homeCore has a language
/// for that already.
library;

import 'binding.dart';
import 'tap_action.dart';

/// Which way a wire runs.
enum WireWay {
  /// The house drives the page: a reading changes how something looks.
  reads,

  /// The page drives the house: a touch changes something.
  writes,
}

/// One connection between a device and an element.
class Wire {
  const Wire({
    required this.way,
    required this.elementId,
    required this.elementName,
    required this.elementType,
    required this.deviceId,
    required this.key,
    required this.property,
    this.transform,
  });

  final WireWay way;

  final String elementId;
  final String elementName;
  final String elementType;

  /// The device at the other end. For [WireWay.writes] with no device — a page
  /// link — this is the page's id and [key] says so.
  final String deviceId;

  /// The reading, for a wire that reads. The action's verb, for one that
  /// writes: `run`, `set`, `go`.
  final String key;

  /// What it lands on: a property name, or what the action changes.
  final String property;

  /// The step in the middle, in words, or null when the value passes straight
  /// through.
  ///
  /// **This is the point of drawing it.** A range mapping and a look table are
  /// settings buried two levels inside an inspector, and they are the two
  /// things most likely to be why a page is showing the wrong thing. On a wire
  /// they are a step you can see.
  final String? transform;
}

/// Every wire on one page.
///
/// [elements] is `(id, name, type, config)` for each placement — passed in
/// rather than read from a provider so this stays pure and a test can hand it
/// three maps.
List<Wire> wiresOf(
  Iterable<({String id, String name, String type, Map<String, dynamic> config})>
      elements,
) {
  final wires = <Wire>[];
  for (final element in elements) {
    for (final binding in Bindings.fromConfig(element.config).all) {
      wires.add(Wire(
        way: WireWay.reads,
        elementId: element.id,
        elementName: element.name,
        elementType: element.type,
        deviceId: binding.deviceId,
        key: binding.key,
        property: binding.property,
        transform: _describe(binding),
      ));
    }
    final action = TapAction.fromConfig(element.config);
    if (action != null && action.isComplete) {
      wires.add(Wire(
        way: WireWay.writes,
        elementId: element.id,
        elementName: element.name,
        elementType: element.type,
        deviceId: action.targetId!,
        key: switch (action.action) {
          TapDo.scene => 'run',
          TapDo.mode => 'mode',
          TapDo.set => 'set',
          TapDo.device => 'open',
          TapDo.page => 'go',
        },
        property: switch (action.action) {
          TapDo.set => action.attribute ?? '',
          TapDo.mode => action.toggles ? 'the other way' : '${action.value}',
          _ => '',
        },
      ));
    }
  }
  return wires;
}

/// The transform in words, or null when there is none.
String? _describe(PropertyBinding b) {
  final steps = <String>[];
  if (b.inFrom != null &&
      b.inTo != null &&
      b.outFrom != null &&
      b.outTo != null) {
    steps.add('${_n(b.inFrom!)}–${_n(b.inTo!)} → '
        '${_n(b.outFrom!)}–${_n(b.outTo!)}');
  }
  if (b.map.isNotEmpty) {
    // Named, not listed. Six entries would make the wire unreadable, and the
    // count is what tells you whether to go and look.
    steps.add(b.map.length == 1 ? '1 look' : '${b.map.length} looks');
  }
  if (b.decimals != null) steps.add('${b.decimals} dp');
  if ((b.suffix ?? '').isNotEmpty) steps.add('"${b.suffix}"');
  return steps.isEmpty ? null : steps.join(' · ');
}

String _n(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
