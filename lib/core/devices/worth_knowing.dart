/// What a house wants you to know, as a short list.
///
/// John, on a house page that showed a feed of everything happening: *"the
/// needs you should be items needing attention like low batteries and alerts
/// not house events that flow by constantly."* Those are different questions. A
/// feed answers *what just happened*, which is endless and mostly nothing; this
/// answers *is anything wrong*, which has an end and is usually short.
///
/// **The good news counts too.** A digest of only faults is silent when the
/// house is fine, and silence is indistinguishable from a broken panel — so
/// "nine other doors closed" is an item, in green. That is the difference
/// between a list of problems and a thing you can look at and stop worrying.
///
/// Pure, so what counts as worth knowing is testable without a widget: the
/// rules are the interesting part and they are the part that will grow.
library;

import '../models/device_state.dart';
import 'presentation.dart' show normalizeAreaName;

/// How loudly one line asks to be read.
enum Attention {
  /// Something is wrong now — water on the floor, a battery about to die.
  danger,

  /// Something is open, unlocked, or unreachable. Worth a look, not an alarm.
  warn,

  /// Nothing is wrong, and saying so is the point.
  good,
}

/// One line: a thing, what about it, and how loudly.
typedef Knowing = ({Attention level, String what, String state});

/// A battery reading as a percentage, or null when this device has none.
///
/// Not every `battery` is a percentage — some plugins send `ok`/`low`, some
/// send volts. Only a number in 0–100 is read as one, because reading a
/// voltage as a percentage reports a healthy sensor at 3% and buries the flat
/// one underneath it.
double? batteryPercent(DeviceState d) {
  for (final key in ['battery', 'battery_pct', 'battery_level']) {
    final raw = d.state[key];
    if (raw is num && raw >= 0 && raw <= 100) return raw.toDouble();
  }
  return null;
}

bool _isTrue(Object? v) => v == true;
bool _isFalse(Object? v) => v == false;

/// What the house wants you to know, most urgent first.
///
/// [lowBattery] is the line under which a battery is worth mentioning. Fifty is
/// the mockup's number and a reasonable one: a sensor at 55% will be fine for
/// months, and one at 45% is the thing that dies over a weekend away.
List<Knowing> worthKnowing(
  Iterable<DeviceState> devices, {
  double lowBattery = 50,
  String? room,
}) {
  // Narrowed to one room when asked. The room page wants what needs attention
  // *here*; the house page wants all of it, and the same rules answer both.
  if (room != null && room.isNotEmpty) {
    final want = normalizeAreaName(room);
    devices = devices
        .where((d) => normalizeAreaName(d.effectiveArea) == want)
        .toList();
  }

  final out = <Knowing>[];
  var doorsClosed = 0;
  var sensorsDry = 0;
  var locksLocked = 0;

  for (final d in devices) {
    final name = d.displayName;

    // Unreachable first: a device that is not answering makes every other
    // reading about it stale, so its battery is not also reported.
    if (!d.available) {
      out.add((level: Attention.warn, what: name, state: 'offline'));
      continue;
    }

    if (_isTrue(d.state['water_detected'])) {
      out.add((level: Attention.danger, what: name, state: 'water'));
    } else if (_isFalse(d.state['water_detected'])) {
      sensorsDry++;
    }

    if (_isTrue(d.state['open'])) {
      out.add((level: Attention.warn, what: name, state: 'open'));
    } else if (_isFalse(d.state['open'])) {
      doorsClosed++;
    }

    if (_isFalse(d.state['locked'])) {
      out.add((level: Attention.warn, what: name, state: 'unlocked'));
    } else if (_isTrue(d.state['locked'])) {
      locksLocked++;
    }

    if (batteryPercent(d) case final pct? when pct <= lowBattery) {
      out.add((
        level: Attention.danger,
        what: name,
        state: '${pct.round()}% battery',
      ));
    }
  }

  out.sort((a, b) {
    final byLevel = a.level.index.compareTo(b.level.index);
    return byLevel != 0 ? byLevel : a.what.compareTo(b.what);
  });

  // The reassurances, after everything that is actually wrong. Phrased as
  // "other" because the ones that are not fine are listed above and counting
  // them twice would be a panel arguing with itself.
  if (doorsClosed > 0) {
    out.add((
      level: Attention.good,
      what: '$doorsClosed other ${doorsClosed == 1 ? "door" : "doors"}',
      state: 'closed',
    ));
  }
  if (locksLocked > 0) {
    out.add((
      level: Attention.good,
      what: '$locksLocked ${locksLocked == 1 ? "lock" : "locks"}',
      state: 'locked',
    ));
  }
  if (sensorsDry > 0) {
    out.add((
      level: Attention.good,
      what: '$sensorsDry leak ${sensorsDry == 1 ? "sensor" : "sensors"}',
      state: 'dry',
    ));
  }
  return out;
}
