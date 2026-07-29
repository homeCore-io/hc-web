/// Notification channels — the `[[notify.channels]]` block, as data.
///
/// A channel is a name plus a provider, and the provider decides the rest of
/// the fields. On the wire it is one flat table per channel, `type` tagging
/// which provider it is — `#[serde(flatten)]` on core's `ProviderConfig`.
library;

/// What a provider needs, so the editor and the validator agree on one list.
class ChannelKind {
  const ChannelKind({
    required this.type,
    required this.label,
    required this.fields,
  });

  final String type;
  final String label;
  final List<ChannelField> fields;

  static const email = ChannelKind(
    type: 'email',
    label: 'Email (SMTP)',
    fields: [
      ChannelField('smtp_host', 'SMTP host', required: true),
      ChannelField('smtp_port', 'Port',
          kind: FieldKind.integer, required: true),
      ChannelField('username', 'Username', required: true),
      ChannelField('password', 'Password', secret: true, required: true),
      ChannelField('from', 'From address', required: true),
      ChannelField('to', 'To addresses', kind: FieldKind.list, required: true),
      ChannelField(
        'starttls',
        'STARTTLS',
        kind: FieldKind.boolean,
        help: 'On for port 587. Off means implicit TLS, which is port 465.',
      ),
    ],
  );

  static const pushover = ChannelKind(
    type: 'pushover',
    label: 'Pushover',
    fields: [
      ChannelField('api_token', 'API token', secret: true, required: true),
      ChannelField('user_key', 'User key', secret: true, required: true),
      ChannelField('device', 'Device',
          help: 'A single device name. Leave empty to reach all of them.'),
      ChannelField('priority', 'Priority',
          kind: FieldKind.integer, help: '-2 to 2. Default 0.'),
    ],
  );

  static const telegram = ChannelKind(
    type: 'telegram',
    label: 'Telegram',
    fields: [
      ChannelField('bot_token', 'Bot token', secret: true, required: true),
      ChannelField('chat_id', 'Chat ID', required: true),
      ChannelField('markdown', 'MarkdownV2', kind: FieldKind.boolean),
    ],
  );

  static const all = [email, pushover, telegram];

  static ChannelKind? forType(String? type) {
    for (final k in all) {
      if (k.type == type) return k;
    }
    return null;
  }
}

enum FieldKind { text, integer, boolean, list }

class ChannelField {
  const ChannelField(
    this.key,
    this.label, {
    this.kind = FieldKind.text,
    this.secret = false,
    this.required = false,
    this.help,
  });

  final String key;
  final String label;
  final FieldKind kind;
  final bool secret;
  final bool required;
  final String? help;
}

/// One configured channel.
class NotifyChannel {
  NotifyChannel({required this.name, required this.type, required this.values});

  String name;
  String type;

  /// Provider fields, keyed as core writes them. Held as-loaded so a save can
  /// send back a secret the user never retyped.
  Map<String, dynamic> values;

  ChannelKind? get kind => ChannelKind.forType(type);

  factory NotifyChannel.fromToml(Map<String, dynamic> row) {
    final values = Map<String, dynamic>.from(row)
      ..remove('name')
      ..remove('type');
    return NotifyChannel(
      name: '${row['name'] ?? ''}',
      type: '${row['type'] ?? ''}',
      values: values,
    );
  }

  /// Flat again, the way core reads it: name and type alongside the provider's
  /// own keys, not nested under them.
  Map<String, dynamic> toToml() => {
        'name': name,
        'type': type,
        ...values,
      };

  NotifyChannel copy() => NotifyChannel(
        name: name,
        type: type,
        values: Map<String, dynamic>.from(values),
      );
}

/// Read the channels out of the parsed config.
///
/// `notify` may be absent entirely (no channel has ever been configured, which
/// is the common case) — that is an empty list, not an error.
List<NotifyChannel> channelsFrom(Map<String, dynamic> parsedConfig) {
  final notify = parsedConfig['notify'];
  if (notify is! Map) return [];
  final list = notify['channels'];
  if (list is! List) return [];
  return [
    for (final row in list)
      if (row is Map) NotifyChannel.fromToml(Map<String, dynamic>.from(row)),
  ];
}

/// Why this channel cannot be saved, or null.
///
/// Named separately from the editor so the rules are testable without a widget,
/// and so the list and the editor cannot disagree about what is valid.
String? validateChannel(NotifyChannel c, List<NotifyChannel> siblings) {
  final name = c.name.trim();
  if (name.isEmpty) {
    return 'Give the channel a name — rules refer to it by name.';
  }
  if (name.contains(' ')) {
    return 'No spaces in a channel name; a rule writes it as a bare word.';
  }
  final clash = siblings.any((o) => !identical(o, c) && o.name.trim() == name);
  if (clash) return 'Another channel is already called “$name”.';

  final kind = c.kind;
  if (kind == null) return 'Pick a provider.';

  for (final f in kind.fields) {
    if (!f.required) continue;
    final v = c.values[f.key];
    final empty = v == null ||
        (v is String && v.trim().isEmpty) ||
        (v is List && v.isEmpty);
    if (empty) return '${f.label} is required.';
  }
  return null;
}

/// True when this value came back from core as a real stored secret.
///
/// The editor shows secrets masked and only sends what was retyped; a field
/// left untouched keeps the value already in the file. Writing the mask back
/// would replace a working password with six dots.
bool isStoredSecret(Object? value) => value is String && value.isNotEmpty;
