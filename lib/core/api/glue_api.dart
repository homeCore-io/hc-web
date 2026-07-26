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

  /// Reconfigure an existing helper.
  ///
  /// The command surface *operates* a helper — sets a number's value, picks a
  /// select's option. It cannot change what the helper IS, so before this the
  /// only way to fix a select's options or a group's members was to delete and
  /// recreate, which breaks every rule referring to it.
  Future<void> update(String id, Map<String, Object?> config) async {
    await client.dio.patch('/glue/$id', data: {'config': config});
  }

  /// Rename, through the device endpoint that already owns naming.
  ///
  /// Not folded into [update]: `PATCH /devices/:id` sets the user's override
  /// with rules this page has no business reimplementing.
  Future<void> rename(String id, String name) async {
    await client.dio.patch('/devices/$id', data: {'name': name});
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
  GlueType('number', 'Number', 'Holds a value you can set.',
      config: GlueConfig.number),
  GlueType('select', 'Select', 'One of a fixed set of options.',
      config: GlueConfig.select),
  GlueType('text', 'Text', 'Holds a line of text.'),
  GlueType('button', 'Button', 'Fires rules when pressed.'),
  GlueType('datetime', 'Date & time', 'Holds a date or a time.'),
  GlueType('group', 'Group', 'Several devices treated as one.',
      config: GlueConfig.group),
  GlueType('threshold', 'Threshold', 'True when a reading crosses a line.'),
  GlueType('schedule', 'Schedule', 'True inside a time window.'),
];

/// The extra setup a kind needs before it is any use.
///
/// Most kinds are complete with a name. Three are not: a number without a
/// range is a slider from 0 to 100 whatever it measures, a select with no
/// options can never be set to anything, and a group with no members is a
/// device that reports on nothing. Creating those bare means editing them
/// somewhere else immediately, so the dialog asks.
enum GlueConfig { none, number, select, group }

class GlueType {
  const GlueType(this.id, this.label, this.blurb,
      {this.config = GlueConfig.none});

  /// The `type` the API expects, and the device_type it writes.
  final String id;
  final String label;

  /// One line on what it is FOR — the list is otherwise eleven nouns.
  final String blurb;

  /// What else the create dialog has to ask for.
  final GlueConfig config;
}

GlueType? glueTypeFor(String? deviceType) {
  for (final t in kGlueTypes) {
    if (t.id == deviceType) return t;
  }
  return null;
}
