import 'homecore_client.dart';

/// One line of the audit trail: who did what, to what, and whether it worked.
///
/// Core has kept this since auth landed — actor, event, target, scope, address,
/// result, with configurable retention — and no Flutter screen has ever read
/// it. Every field below exists on the wire; nothing here is derived.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.at,
    required this.actorType,
    required this.actorLabel,
    required this.eventType,
    required this.result,
    this.actorId,
    this.scopeUsed,
    this.targetKind,
    this.targetId,
    this.correlationId,
    this.ip,
    this.userAgent,
    this.detail,
  });

  final int? id;
  final DateTime at;

  /// `user` · `api_key` · `local_admin` · `ip_whitelist` · `system` ·
  /// `anonymous` — core's closed set, parsed server-side, so an unknown value
  /// here means the server got newer than this client.
  final String actorType;

  /// Already human-facing: a username, an API key label, or for a failed
  /// sign-in `attempted_username:<what they typed>`.
  final String actorLabel;
  final String? actorId;

  /// Dotted, `<noun>.<verb>`: `auth.login`, `api_key.created`,
  /// `system.config_updated`.
  final String eventType;

  /// `success` · `denied` · `error`.
  final String result;
  final String? scopeUsed;
  final String? targetKind;
  final String? targetId;
  final String? correlationId;
  final String? ip;
  final String? userAgent;

  /// Free-form, per event type. Deliberately never contains config *values* —
  /// core records which sections changed, not what they changed to, because
  /// they hold passwords and tokens.
  final Map<String, dynamic>? detail;

  bool get denied => result == 'denied';
  bool get failed => result != 'success';

  /// The noun half of the event type — `auth` from `auth.login`. What the
  /// filter chips group on.
  String get eventClass {
    final dot = eventType.indexOf('.');
    return dot < 0 ? eventType : eventType.substring(0, dot);
  }

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        id: (j['id'] as num?)?.toInt(),
        // A row without a parseable timestamp is not worth dropping the page
        // over; it sorts to the epoch and stays visible.
        at: DateTime.tryParse('${j['ts']}')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        actorType: j['actor_type'] as String? ?? 'unknown',
        actorLabel: j['actor_label'] as String? ?? '',
        actorId: j['actor_id'] as String?,
        eventType: j['event_type'] as String? ?? '',
        result: j['result'] as String? ?? 'success',
        scopeUsed: j['scope_used'] as String?,
        targetKind: j['target_kind'] as String?,
        targetId: j['target_id'] as String?,
        correlationId: j['correlation_id'] as String?,
        ip: j['ip'] as String?,
        userAgent: j['user_agent'] as String?,
        detail: j['detail'] is Map
            ? Map<String, dynamic>.from(j['detail'] as Map)
            : null,
      );
}

/// What to ask the server for. Everything is optional; core defaults `limit` to
/// 100, which is small enough to be surprising on a page that scrolls.
class AuditFilter {
  const AuditFilter({
    this.actorType,
    this.eventType,
    this.targetKind,
    this.targetId,
    this.result,
    this.from,
    this.to,
    this.limit = 250,
    this.offset = 0,
  });

  final String? actorType;
  final String? eventType;
  final String? targetKind;
  final String? targetId;
  final String? result;
  final DateTime? from;
  final DateTime? to;
  final int limit;
  final int offset;

  Map<String, dynamic> toQuery() => {
        if (actorType != null) 'actor_type': actorType,
        if (eventType != null) 'event_type': eventType,
        if (targetKind != null) 'target_kind': targetKind,
        if (targetId != null) 'target_id': targetId,
        if (result != null) 'result': result,
        if (from != null) 'from': from!.toUtc().toIso8601String(),
        if (to != null) 'to': to!.toUtc().toIso8601String(),
        'limit': limit,
        'offset': offset,
      };
}

class AuditApi {
  AuditApi(this.client);
  final HomecoreClient client;

  Future<List<AuditEntry>> list(AuditFilter filter) async {
    final res =
        await client.dio.get('/audit', queryParameters: filter.toQuery());
    return [
      for (final row in (res.data as List))
        AuditEntry.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }
}
