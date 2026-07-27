import 'package:flutter/material.dart';

import '../../core/models/device_state.dart';
import '../../core/text/humanize.dart';
import '../../design/tokens.dart';

/// Everything a device reports but you cannot set, said in units and grouped.
///
/// The exhibit this exists for is the weather station: seventeen attributes, all
/// rendered at the same 12.5px weight with no units at all, so
/// `barometric_abs 29.226` sat beside `temperature 82.4` as an equal, and
/// "is it hot out" took as long to answer as "what is the vapour-pressure
/// deficit". `battery_kind: voltage` and `datetime` were facts in their own
/// right rather than qualifiers of the values they describe.
///
/// The lexicon below is deliberately small. An attribute it does not recognise
/// keeps the old behaviour — humanised name, raw value, "Other" — because a
/// wrong unit is worse than no unit.
class DeviceReadingsBlock extends StatefulWidget {
  const DeviceReadingsBlock({
    super.key,
    required this.device,
    this.hide = const {},
  });

  final DeviceState device;

  /// Attributes another block already renders — the hero's metric, the writable
  /// ones the Controls block owns. Passed in rather than recomputed so the two
  /// cannot drift into showing the same value twice.
  final Set<String> hide;

  @override
  State<DeviceReadingsBlock> createState() => _DeviceReadingsBlockState();
}

class _DeviceReadingsBlockState extends State<DeviceReadingsBlock> {
  bool _advancedOpen = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final s = widget.device.state;

    final keys = s.keys.where((k) {
      if (widget.hide.contains(k)) return false;
      if (isReadingMetadata(k)) return false;
      // The raw twin of a percentage: a light reports `brightness` and
      // `brightness_pct`; keep the one with a unit.
      if (!k.endsWith('_pct') && s.containsKey('${k}_pct')) return false;
      return true;
    }).toList();

    final advanced = keys.where(isAdvancedReading).toList();
    final normal = keys.where((k) => !isAdvancedReading(k)).toList();
    if (normal.isEmpty && advanced.isEmpty) return const SizedBox.shrink();

    // Group, then order the groups so the ones a person came for lead.
    final grouped = <String, List<String>>{};
    for (final k in normal) {
      grouped.putIfAbsent(readingGroup(k), () => []).add(k);
    }
    final order = [
      for (final g in kReadingGroupOrder)
        if (grouped.containsKey(g)) g,
      for (final g in grouped.keys)
        if (!kReadingGroupOrder.contains(g)) g,
    ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final g in order) ...[
            // A single group is the whole block; naming it would be a heading
            // over one thing.
            if (order.length > 1) ...[
              SizedBox(height: t.space.xs),
              Text(
                g.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: t.surface.onBaseMuted,
                ),
              ),
              SizedBox(height: t.space.xs),
            ],
            for (final k in grouped[g]!)
              _Row(
                  name: readingName(k), value: formatReading(widget.device, k)),
          ],
          if (advanced.isNotEmpty) ...[
            SizedBox(height: t.space.xs),
            InkWell(
              onTap: () => setState(() => _advancedOpen = !_advancedOpen),
              borderRadius: t.radius.smR,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: t.space.sm),
                child: Row(
                  children: [
                    Text('Advanced · ${advanced.length}',
                        style: TextStyle(
                            fontSize: 12.5, color: t.surface.onBaseMuted)),
                    const Spacer(),
                    Icon(
                        _advancedOpen
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: t.surface.onBaseMuted),
                  ],
                ),
              ),
            ),
            if (_advancedOpen)
              for (final k in advanced)
                _Row(
                    name: readingName(k),
                    value: formatReading(widget.device, k)),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.name, required this.value});

  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(name,
              style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted)),
          SizedBox(width: t.space.md),
          // Expanded, not Spacer + Flexible. Two flexible children split the
          // free space between them, so the value box hugged its text at a
          // different x on every row and `textAlign: right` had nothing to
          // align against — the values came out visibly ragged.
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: t.surface.onBase,
                fontFeatures: t.numericFontFeatures,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── the lexicon ──────────────────────────────────────────────────────────────

const kReadingGroupOrder = ['Air', 'Wind', 'Sky', 'Power', 'Status', 'Other'];

const _groups = <String, String>{
  'temperature': 'Air',
  'current_temperature': 'Air',
  'humidity': 'Air',
  'barometric_rel': 'Air',
  'barometric_abs': 'Air',
  'pressure': 'Air',
  'vpd': 'Air',
  'co2': 'Air',
  'pm25': 'Air',
  'wind_speed': 'Wind',
  'gust_speed': 'Wind',
  'wind_direction': 'Wind',
  'wind_direction_avg10m': 'Wind',
  'daily_max_wind': 'Wind',
  'light': 'Sky',
  'illuminance': 'Sky',
  'illuminance_lux': 'Sky',
  'uvi': 'Sky',
  'rain_rate': 'Sky',
  'power': 'Power',
  'voltage': 'Power',
  'current': 'Power',
  'energy': 'Power',
  'battery': 'Status',
  'signal': 'Status',
  'rssi': 'Status',
  'last_alert': 'Status',
};

String readingGroup(String attr) => _groups[attr] ?? 'Other';

/// Bookkeeping, or a qualifier that belongs *on* the value it describes rather
/// than in a row of its own.
bool isReadingMetadata(String key) {
  final k = key.toLowerCase();
  return k.endsWith('_unit') ||
      const {
        'name',
        'kind',
        'bridge_id',
        'resource_id',
        'plugin_id',
        'group_rid',
        'group_name',
        'group_kind',
        'area',
        // Folded into `battery`.
        'battery_kind',
        'battery_low',
        // Catalogues a picker consumes; as a row they are a wall of JSON.
        'available_apps',
        'available_inputs',
        'available_sources',
        'available_tv_channels',
        'available_buttons',
        'available_favorites',
        'available_favorite_items',
        'available_playlists',
        'available_playlist_items',
        'supported_actions',
        'ui_enrichments',
        'effect_values',
        'sonos',
        'device_info',
        'media_image_url',
      }.contains(k) ||
      _isIdentity(k);
}

/// Identity and capability, which a Roku publishes a great deal of.
///
/// `Is TV: Yes`, `Supports Wake On Lan: Yes`, `Model Number: 8116X` — twenty-odd
/// rows of them, none of which is a *reading*. They tell the client what the
/// device can do (the panel consumes them by gating controls) and what it is
/// (the Details fold's job). Neither is something you open a panel to check.
bool _isIdentity(String k) =>
    k.startsWith('supports_') ||
    k.startsWith('is_') ||
    k.endsWith('_enabled') ||
    const {
      'friendly_name',
      'model_name',
      'model_number',
      'serial_number',
      'software_version',
      'network_type',
      'app_id',
      'app_type',
      'app_version',
      'media_format',
      'media_error',
      'media_is_live',
      'player_state',
      'screensaver_name',
      'auto_lock_secs',
      // Hue effect plumbing: which dynamic scene is running and how fast. Not
      // a reading, and the effects themselves are verbs.
      'dynamic_speed',
      'dynamic_status',
      'supports_gradient',
      'supports_dimming',
      'supports_identify',
      'supports_color_xy',
    }.contains(k);

/// Z-Wave (and similar) command-class dumps — real data, but noise.
final _ccAttr = RegExp(r'^cc\d+_');
bool isAdvancedReading(String key) => _ccAttr.hasMatch(key);

/// A metric's name without the unit suffix that is about to be rendered anyway.
String readingName(String attr) {
  const special = {
    'vpd': 'Vapour deficit',
    'barometric_rel': 'Pressure',
    'barometric_abs': 'Pressure (absolute)',
    'uvi': 'UV index',
    'daily_max_wind': 'Max wind today',
    'wind_direction_avg10m': 'Direction, 10 min avg',
    'gust_speed': 'Gust',
    'light': 'Light',
    'rssi': 'Signal',
  };
  if (special[attr] case final s?) return s;

  var s = attr;
  for (final suffix in const ['_pct', '_lux', '_secs', '_f', '_c']) {
    if (s.endsWith(suffix)) {
      s = s.substring(0, s.length - suffix.length);
      break;
    }
  }
  return humanize(s);
}

/// The value, in the unit the device meant.
///
/// Units come from a lexicon rather than from the number, because the number
/// cannot tell you: `3.0` is volts on one sensor and a percentage on another.
String formatReading(DeviceState d, String attr) {
  final v = d.state[attr];

  if (v == null) return '—';
  if (v is bool) return _boolWord(attr, v);
  if (v is List) return v.isEmpty ? 'none' : '${v.length} items';
  if (v is Map) return '${v.length} fields';
  if (v is! num) return '$v';

  // Wind direction is a bearing, and a bearing has a name.
  if (attr.startsWith('wind_direction')) {
    return '${v.round()}° ${_compass(v.toDouble())}';
  }
  if (attr == 'battery') return _battery(d, v);

  final unit = _unitFor(d, attr);
  final shown = v == v.roundToDouble() && v.abs() < 100000
      ? v.round().toString()
      : v.toStringAsFixed(2);
  return '$shown$unit';
}

String _unitFor(DeviceState d, String attr) {
  switch (attr) {
    case 'temperature' || 'current_temperature' || 'setpoint':
      final u = d.state['temperature_unit'];
      return '°${u is String && u.isNotEmpty ? u.replaceAll('°', '') : ''}';
    case 'barometric_rel' || 'barometric_abs':
      return ' inHg';
    case 'vpd':
      return ' kPa';
    case 'wind_speed' || 'gust_speed' || 'daily_max_wind':
      return ' mph';
    case 'light':
      return ' W/m²';
    case 'uvi':
      return '';
    case 'co2':
      return ' ppm';
    case 'pm25':
      return ' µg/m³';
    case 'power':
      return ' W';
    case 'voltage':
      return ' V';
    case 'energy':
      return ' kWh';
    case 'rssi' || 'signal':
      return ' dBm';
  }
  final a = attr.toLowerCase();
  if (a.endsWith('_pct') || a.contains('humid')) return '%';
  if (a.endsWith('_secs')) return ' s';
  if (a.contains('lux') || a.contains('illumin')) return ' lux';
  return '';
}

/// A battery reading with its kind folded in — the whole point of
/// `core/devices/battery.dart`, applied to the row as well as the alert.
String _battery(DeviceState d, num raw) {
  final low = d.state['battery_low'];
  return switch (d.state['battery_kind']) {
    'binary' => low == true ? 'Low' : 'OK',
    'level' => 'Level ${raw.round()}${low == true ? ' · low' : ''}',
    'voltage' => '${raw.toStringAsFixed(1)} V${low == true ? ' · low' : ''}',
    _ => '${raw.round()}%',
  };
}

String _boolWord(String attr, bool v) {
  final a = attr.toLowerCase();
  if (a.contains('leak') || a.contains('water')) return v ? 'Detected' : 'Dry';
  if (a.contains('smoke')) return v ? 'Detected' : 'Clear';
  if (a == 'open') return v ? 'Open' : 'Closed';
  // `contact` is deliberately NOT translated to open/closed.
  //
  // The electrical convention says a closed contact circuit means the door is
  // shut, so `true` would read as "Closed". But every YoLink door sensor on the
  // live install reports `contact: false` *alongside* `open: false` — the same
  // door, described two ways, and under that convention they contradict each
  // other. One of the two plugins is using the opposite sense and the client
  // cannot tell which from the value alone.
  //
  // So it stays a neutral Yes/No until a plugin declares the pair via
  // `AttributeSchema.states`, which exists for exactly this. A confident wrong
  // word about whether a door is open is worse than an unhelpful true one.
  if (a.contains('motion')) return v ? 'Motion' : 'Clear';
  if (a.contains('occup')) return v ? 'Occupied' : 'Empty';
  if (a.contains('muted')) return v ? 'Muted' : 'Not muted';
  return v ? 'Yes' : 'No';
}

/// 16-point compass. A bearing rendered as a bare number is data the reader has
/// to decode; the name is the same value, already read.
String _compass(double deg) {
  const points = [
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', //
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
  ];
  final i = (((deg % 360) / 22.5) + 0.5).floor() % 16;
  return points[i];
}
