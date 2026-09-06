import '../models/device_state.dart';
import 'presentation.dart';

/// A number about the whole house rather than about one device.
///
/// **A page that says "7 LIGHTS ON" has to be able to mean it.** The house
/// page said it for months and did not: the number was written into the page
/// when the page was generated, so it stayed 7 while the lights went on and
/// off underneath it. A binding cannot answer this — it follows a device, and
/// this is a question about all of them — so it is asked here and spelled the
/// way the author asks for it.
///
/// The facet decides what a light is, never `device_type`: a Lutron dimmer
/// publishes itself as a switch, and a relay somebody has retyped carries that
/// in `ui_hint`. [DeviceFacet.isLight] is the same answer the room field and
/// the room pages give, which is the whole reason it exists.
int houseTally(String metric, List<DeviceState> devices) => switch (metric) {
      'devices' => devices.length,
      'lights' => devices.where((d) => facetOf(d).isLight).length,
      'lights_on' => devices
          .where((d) => facetOf(d).isLight && d.state['on'] == true)
          .length,
      'offline' => devices.where((d) => !d.available).length,
      'playing' => devices
          .where((d) => d.isMediaPlayer && d.playbackState == 'playing')
          .length,
      // An unknown tally is not a zero: it is a page asking for something this
      // build has never heard of, and answering "0 lights on" would be a lie
      // told confidently. The caller keeps the author's own words instead.
      _ => -1,
    };

/// The metrics [houseTally] knows, in the order the inspector offers them.
const houseTallyMetrics = <String>[
  'devices',
  'lights',
  'lights_on',
  'offline',
  'playing',
];
