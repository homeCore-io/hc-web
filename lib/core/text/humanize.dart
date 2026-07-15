/// Turns a backend identifier into human English for display.
///
/// `family_room` → "Family Room", `bedroom_3` → "Bedroom 3",
/// `temperature_sensor` → "Temperature Sensor". Every surface that shows an
/// area key, a device type, a plugin id, or any other raw identifier runs it
/// through here, so `snake_case` never reaches a person.
///
/// It is NOT for a device's own display name — those already arrive human
/// (`Master Bedroom AC`, `iHeartRadio`, `WLED`), and title-casing them would
/// wreck the mixed-case ones. Use it on identifiers, not on names.
library;

/// Words that must not be title-cased into "Ac"/"Led"/"Tv".
const _acronyms = <String, String>{
  'ac': 'AC',
  'led': 'LED',
  'tv': 'TV',
  'uv': 'UV',
  'rgb': 'RGB',
  'rgbw': 'RGBW',
  'hvac': 'HVAC',
  'usb': 'USB',
  'ip': 'IP',
  'id': 'ID',
  'ir': 'IR',
  'oh1': 'OH1',
  'oh2': 'OH2',
  'vcrx': 'VCRX',
  'co2': 'CO₂',
  'pm25': 'PM2.5',
};

String humanize(String? raw) {
  if (raw == null) return '';
  final words = raw.trim().split(RegExp(r'[_\s]+')).where((w) => w.isNotEmpty);
  return words.map((w) {
    final lower = w.toLowerCase();
    final acr = _acronyms[lower];
    if (acr != null) return acr;
    return w[0].toUpperCase() + w.substring(1);
  }).join(' ');
}
