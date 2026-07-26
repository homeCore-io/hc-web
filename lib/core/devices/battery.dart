import '../models/device_state.dart';

/// How a device reports its battery — because `battery: 0` is not one fact.
///
/// The client used to read every `battery` value as a percentage, which is only
/// true for some plugins. hc-ecowitt publishes three other conventions
/// (`plugins/hc-ecowitt/src/battery.rs`), and under the percentage reading they
/// all come out wrong in the same direction:
///
///   * `binary` — `0` = OK, `1` = LOW. Read as a percentage, a **healthy**
///     sensor reports "0% battery" and a **flat** one reports "1%", so the two
///     sensors that are actually dead sort as *less* urgent than the six that
///     are fine.
///   * `level` — a discrete 0..5 or 0..6 scale. A lightning sensor sitting at
///     level 2 of 5 reads as "2% battery".
///   * `voltage` — raw cell volts. A fresh 3 V pair reads as "3% battery".
///
/// On the live install that was ten alerts of which two were real. A count that
/// is permanently wrong is worse than no count, because you learn to ignore it.
///
/// The plugin already does the classification and publishes the answer as
/// `battery_low`; this is the client finally reading it.
enum BatteryKind {
  /// The default when a device says nothing else — a 0–100 percentage.
  percent,

  /// `0` = OK, anything `>= 1` = low.
  binary,

  /// A discrete 0..N scale, low at the bottom step or two.
  level,

  /// Raw cell voltage. The low threshold is model-specific and known only to
  /// the plugin, so a client never infers "low" from volts on its own.
  voltage,
}

/// The percentage at or below which a *percentage* battery is a problem.
///
/// Applies to [BatteryKind.percent] alone. The other kinds carry the plugin's
/// own verdict in `battery_low` and are never compared against this.
const kLowBatteryPct = 25;

/// A device's battery, read the way the device meant it.
class BatteryReading {
  const BatteryReading({
    required this.raw,
    required this.kind,
    required this.low,
  });

  /// The value as published, in whatever unit [kind] implies.
  final double raw;
  final BatteryKind kind;

  /// Whether this needs attention. For every kind but [BatteryKind.percent]
  /// this is the plugin's own `battery_low`, not a guess.
  final bool low;

  /// The reading for a column or a chip: a percentage only when it is one.
  String get label => switch (kind) {
        BatteryKind.percent => '${raw.round()}%',
        BatteryKind.binary => low ? 'low' : 'OK',
        BatteryKind.level => 'level ${raw.round()}',
        BatteryKind.voltage => '${raw.toStringAsFixed(1)} V',
      };

  /// How the problem is worded when this device is listed as needing
  /// attention. "0% battery" on a healthy binary sensor was the whole bug, so
  /// only a percentage is ever phrased as one.
  String get problemReason =>
      kind == BatteryKind.percent ? '${raw.round()}% battery' : 'battery low';
}

/// The battery a device reports, or null if it has none.
BatteryReading? batteryOf(DeviceState d) {
  if (d.state['battery'] case final num raw) {
    final kind = switch (d.state['battery_kind']) {
      'binary' => BatteryKind.binary,
      'level' => BatteryKind.level,
      'voltage' => BatteryKind.voltage,
      _ => BatteryKind.percent,
    };
    return BatteryReading(
      raw: raw.toDouble(),
      kind: kind,
      low: _isLow(d, kind, raw.toDouble()),
    );
  }
  return null;
}

/// Whether a device's battery needs attention. False when it has no battery.
bool hasLowBattery(DeviceState d) => batteryOf(d)?.low ?? false;

/// Ordering for the battery sort, worst first.
///
/// The kinds are not comparable to each other — level 2 of 5 is not "worse" or
/// "better" than 2.6 volts — so the sort ranks by *severity band* first and
/// only orders within the percentage band, where the numbers mean the same
/// thing. Bands: low (0–99) · healthy percentage (100–200) · healthy other
/// (500) · no battery (999).
double batterySortKey(DeviceState d) {
  final r = batteryOf(d);
  if (r == null) return 999;
  if (r.low) return r.kind == BatteryKind.percent ? r.raw : 50;
  return r.kind == BatteryKind.percent ? 100 + r.raw : 500;
}

bool _isLow(DeviceState d, BatteryKind kind, double raw) {
  // The plugin's verdict always wins — it is the only party that knows a
  // sensor model's voltage threshold or how many steps its level scale has.
  if (d.state['battery_low'] case final bool low) return low;

  return switch (kind) {
    BatteryKind.percent => raw <= kLowBatteryPct,
    BatteryKind.binary => raw >= 1,
    BatteryKind.level => raw <= 1,
    // Volts alone say nothing without the model's threshold. A device that
    // publishes `voltage` without `battery_low` is a plugin bug; guessing here
    // would just reintroduce this one.
    BatteryKind.voltage => false,
  };
}
