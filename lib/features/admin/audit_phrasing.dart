import 'package:flutter/material.dart';

import '../../core/api/audit_api.dart';
import '../../core/text/humanize.dart';

/// Turning an audit row into English — and never *instead of* the raw record.
///
/// Everything here is a pure function of one entry so it can be tested without
/// mounting a widget, and so the page has no opinions of its own about what an
/// event means.

/// The label for an event-class filter chip: `api_key` → "API keys".
///
/// The plain [humanize] of a class is usually right ("plugin" → "Plugin"), so
/// this only carries the ones where it is not, and pluralises the rest.
String auditClassLabel(String eventClass) => switch (eventClass) {
      'auth' => 'Sign-ins',
      'api_key' => 'API keys',
      'user' => 'Users',
      'system' => 'System',
      'plugin' => 'Plugins',
      'device' => 'Devices',
      'automation' || 'rule' => 'Automations',
      'area' => 'Areas',
      'scene' => 'Scenes',
      _ => humanize(eventClass),
    };

IconData auditActorIcon(String actorType) => switch (actorType) {
      'user' => Icons.person_outline,
      'api_key' => Icons.key_outlined,
      'local_admin' => Icons.terminal_outlined,
      'ip_whitelist' => Icons.lan_outlined,
      'system' => Icons.memory_outlined,
      'anonymous' => Icons.help_outline,
      _ => Icons.circle_outlined,
    };

/// Who this was, said the way a person would say it.
///
/// A failed sign-in carries `attempted_username:<what they typed>` — showing
/// that raw is both ugly and misleading, because the string is *not* a user of
/// this house. It reads as "tried: bob".
String auditActorName(AuditEntry e) {
  const attempted = 'attempted_username:';
  if (e.actorLabel.startsWith(attempted)) {
    final who = e.actorLabel.substring(attempted.length);
    return who.isEmpty ? 'tried: (blank)' : 'tried: $who';
  }
  if (e.actorLabel.isNotEmpty) return e.actorLabel;
  return humanize(e.actorType);
}

/// What happened, as a sentence.
///
/// Deliberately built from the event's own two halves — `<noun>.<verb>` — with
/// a small table only for the ones a generic reading gets wrong. An event type
/// this client has never heard of still renders as English rather than falling
/// through to a blank cell, which matters because core gains event types
/// without asking the client first.
String auditPhrase(AuditEntry e) {
  final subject = _subjectOf(e);

  final phrase = switch (e.eventType) {
    'auth.login' => e.result == 'success' ? 'Signed in' : 'Sign-in refused',
    'auth.logout' => 'Signed out',
    'auth.refresh' => 'Renewed their session',
    'auth.password_changed' => 'Changed a password',
    'system.config_updated' => 'Changed configuration',
    'system.backup_created' => 'Downloaded a backup',
    'system.restore' => 'Restored from a backup',
    'system.restart' => 'Restarted core',
    'plugin.log_level_changed' => 'Changed the log level',
    _ => _generic(e),
  };

  return subject.isEmpty ? phrase : '$phrase $subject';
}

/// `api_key.created` → "Created API key". Verbs arrive past-tense
/// (`created`, `revoked`, `updated`) or bare (`install`); both read correctly
/// as the head of the sentence.
String _generic(AuditEntry e) {
  final dot = e.eventType.indexOf('.');
  if (dot < 0) return humanize(e.eventType);
  final noun = e.eventType.substring(0, dot);
  final verb = e.eventType.substring(dot + 1).replaceAll('.', ' ');
  return '${humanize(verb)} ${auditNoun(noun)}';
}

/// The singular noun for an event class, mid-sentence.
///
/// Deliberately not `auditClassLabel(...).toLowerCase()`: that reads "Created
/// api key", because lowercasing a label is not the inverse of title-casing an
/// identifier once acronyms are involved. Same reason [humanize] carries an
/// acronym table.
String auditNoun(String eventClass) => switch (eventClass) {
      'auth' => 'sign-in',
      'automation' || 'rule' => 'automation',
      // `api_key` → humanize → "API Key" → "API key": lowercase every word
      // except the ones humanize deliberately left as acronyms.
      _ => humanize(eventClass)
          .split(' ')
          .map(
              (w) => w.length > 1 && w == w.toUpperCase() ? w : w.toLowerCase())
          .join(' '),
    };

/// The thing acted on, if the row names one.
///
/// Prefers the human name core put in `detail` (a username, an API key label,
/// a filename) over `target_id`, which is a UUID on exactly the events where a
/// person would want the name.
String _subjectOf(AuditEntry e) {
  final d = e.detail;
  if (d != null) {
    for (final key in const [
      'username',
      'label',
      'filename',
      'name',
      'level'
    ]) {
      final v = d[key];
      if (v is String && v.isNotEmpty) return '“$v”';
    }
    final sections = d['sections'];
    if (sections is List && sections.isNotEmpty) {
      return sections.length == 1
          ? '[${sections.first}]'
          : '${sections.length} sections';
    }
  }
  final id = e.targetId;
  if (id != null && id.isNotEmpty && !_looksLikeUuid(id)) return id;
  return '';
}

bool _looksLikeUuid(String s) =>
    s.length == 36 && s[8] == '-' && s[13] == '-' && s[18] == '-';

/// One `detail` value, flattened for a key/value row. A list of scopes is the
/// common case and reads far better comma-joined than as JSON.
String auditDetailValue(Object? value) {
  if (value == null) return '—';
  if (value is List) return value.join(', ');
  if (value is Map) {
    return value.entries.map((e) => '${e.key}: ${e.value}').join(' · ');
  }
  return '$value';
}

/// A day of entries, newest day first, entries newest first within it.
class AuditDay {
  const AuditDay(this.label, this.entries);
  final String label;
  final List<AuditEntry> entries;
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Group by calendar day *in the timezone being displayed*.
///
/// Passing [utc] through matters: near midnight the same row belongs to
/// different days in local and UTC, and a heading that disagrees with the
/// timestamps beneath it is worse than no heading.
List<AuditDay> groupByDay(List<AuditEntry> entries, {required bool utc}) {
  final sorted = [...entries]..sort((a, b) => b.at.compareTo(a.at));
  final now = utc ? DateTime.now().toUtc() : DateTime.now();
  final out = <AuditDay>[];
  String? currentKey;

  for (final e in sorted) {
    final at = utc ? e.at.toUtc() : e.at.toLocal();
    final key = '${at.year}-${at.month}-${at.day}';
    if (key != currentKey) {
      currentKey = key;
      out.add(AuditDay(_dayLabel(at, now), []));
    }
    out.last.entries.add(e);
  }
  return out;
}

String _dayLabel(DateTime at, DateTime now) {
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(at.year, at.month, at.day))
      .inDays;
  final date = '${at.day} ${_months[at.month - 1]}';
  return switch (days) {
    0 => 'Today · $date',
    1 => 'Yesterday · $date',
    _ => at.year == now.year ? date : '$date ${at.year}',
  };
}
