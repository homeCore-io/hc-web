import 'homecore_client.dart';

/// The devices core provides itself — timers, counters, switches, flags.
///
/// They have had unified CRUD on the hub (`GET/POST /glue`, `DELETE /glue/:id`)
/// with no client for it, so the only way to make a timer was to POST by hand.
/// They show up in the device list once they exist, but nothing could create
/// one, and nothing could delete one.
class GlueApi {
  const GlueApi(this.client);

  final HomecoreClient client;

  Future<List<Map<String, dynamic>>> list() async {
    final response = await client.dio.get('/glue');
    return List<Map<String, dynamic>>.from(response.data as List);
  }

  /// Create a helper. `type` is one of [kGlueTypes]; the hub adds the id
  /// prefix if it is missing.
  Future<void> create(
    String type,
    String id,
    String name, {
    Map<String, Object?> config = const {},
  }) async {
    await client.dio.post('/glue', data: {
      'type': type,
      'id': id,
      'name': name,
      if (config.isNotEmpty) 'config': config,
    });
  }

  Future<void> delete(String id) async {
    await client.dio.delete('/glue/$id');
  }
}

/// The helper kinds the hub accepts, mirroring `GLUE_TYPES` in hc-api.
///
/// Ordered by how often you reach for one rather than alphabetically: a timer
/// and a switch are the everyday cases, a threshold and a schedule are not.
const kGlueTypes = <GlueType>[
  GlueType('timer', 'Timer', 'Counts down, then fires a rule.'),
  GlueType('switch', 'Switch', 'A flag rules can set and read.'),
  GlueType('counter', 'Counter', 'Counts things up and down.'),
  GlueType('number', 'Number', 'Holds a value you can set.'),
  GlueType('select', 'Select', 'One of a fixed set of options.'),
  GlueType('text', 'Text', 'Holds a line of text.'),
  GlueType('button', 'Button', 'Fires rules when pressed.'),
  GlueType('datetime', 'Date & time', 'Holds a date or a time.'),
  GlueType('group', 'Group', 'Several devices treated as one.'),
  GlueType('threshold', 'Threshold', 'True when a reading crosses a line.'),
  GlueType('schedule', 'Schedule', 'True inside a time window.'),
];

class GlueType {
  const GlueType(this.id, this.label, this.blurb);

  /// The `type` the API expects, and the device_type it writes.
  final String id;
  final String label;

  /// One line on what it is FOR — the list is otherwise eleven nouns.
  final String blurb;
}

GlueType? glueTypeFor(String? deviceType) {
  for (final t in kGlueTypes) {
    if (t.id == deviceType) return t;
  }
  return null;
}
