/// Core's runtime log setting is an `EnvFilter` **directive string**, not a
/// level.
///
/// A running house reports things like `debug,rumqttc::state=info,rumqttd=info`
/// — a global default of debug, plus two targets pinned quieter because the
/// MQTT broker is deafening at debug and drowns everything worth reading.
///
/// That is why this file exists. A control that offers five levels and PUTs the
/// bare word `info` would throw those two target rules away. The request would
/// succeed, the screen would say "info", and the log would fill with broker
/// chatter that looks like a bug somewhere else entirely. So: parse the
/// directive, change only the part that sets the default, and put every other
/// part back exactly as it came.
library;

/// The levels `tracing` understands, quietest last.
const logLevels = <String>['trace', 'debug', 'info', 'warn', 'error'];

class LogLevelDirective {
  const LogLevelDirective._({
    required this.parts,
    required this.defaultIndex,
    required this.ambiguous,
  });

  /// Every comma-separated part, trimmed, in the order core sent them. Order is
  /// preserved rather than normalised: this string round-trips back to core,
  /// and reordering someone's hand-written filter is not ours to do.
  final List<String> parts;

  /// Index into [parts] of the bare directive that sets the global default, or
  /// -1 when every part is scoped to a target and there is no global default.
  final int defaultIndex;

  /// More than one bare directive. Legal, and which one wins is not obvious
  /// enough to guess at, so the quick picks stand down and leave it to the
  /// text field.
  final bool ambiguous;

  factory LogLevelDirective.parse(String raw) {
    final parts = raw
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList(growable: false);

    var first = -1;
    var bare = 0;
    for (var i = 0; i < parts.length; i++) {
      if (!parts[i].contains('=')) {
        bare++;
        if (first < 0) first = i;
      }
    }
    return LogLevelDirective._(
      parts: parts,
      defaultIndex: first,
      ambiguous: bare > 1,
    );
  }

  /// The global default level, lowercased, when the directive names exactly
  /// one. Null when it names none, or when [ambiguous].
  String? get defaultLevel => (!ambiguous && defaultIndex >= 0)
      ? parts[defaultIndex].toLowerCase()
      : null;

  /// The `target=level` parts, verbatim — the rules a level change must not
  /// silently discard.
  List<String> get targets => [
        for (var i = 0; i < parts.length; i++)
          if (i != defaultIndex) parts[i],
      ];

  /// Whether swapping the default level is a well-defined edit. False for a
  /// hand-written filter with several bare directives, where "the level" is
  /// not a single thing.
  bool get canSetLevel => !ambiguous;

  /// Whether [defaultLevel] is one of the five the quick picks offer. A
  /// directive can legally say `off`, or a level this build does not know.
  bool get isPlainLevel =>
      defaultLevel != null && logLevels.contains(defaultLevel);

  /// The same directive with the global default set to [level], every target
  /// rule kept, in place.
  LogLevelDirective withDefaultLevel(String level) {
    final next = [...parts];
    if (defaultIndex >= 0) {
      next[defaultIndex] = level;
      return LogLevelDirective._(
        parts: next,
        defaultIndex: defaultIndex,
        ambiguous: ambiguous,
      );
    }
    // No global default yet: EnvFilter reads a bare directive anywhere, but it
    // is written first by convention and reads that way too.
    next.insert(0, level);
    return LogLevelDirective._(
        parts: next, defaultIndex: 0, ambiguous: ambiguous);
  }

  /// Back to the wire format core sent.
  String format() => parts.join(',');

  @override
  String toString() => format();
}
