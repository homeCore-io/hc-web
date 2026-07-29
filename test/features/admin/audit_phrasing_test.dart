import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/audit_api.dart';
import 'package:hc_web/features/admin/audit_phrasing.dart';

AuditEntry _e({
  String event = 'auth.login',
  String result = 'success',
  String actorLabel = 'admin',
  String actorType = 'user',
  String? targetId,
  Map<String, dynamic>? detail,
  DateTime? at,
}) =>
    AuditEntry(
      id: 1,
      at: at ?? DateTime.utc(2026, 7, 27, 23, 48),
      actorType: actorType,
      actorLabel: actorLabel,
      eventType: event,
      result: result,
      targetId: targetId,
      detail: detail,
    );

void main() {
  group('parsing', () {
    test('reads a real row off the wire', () {
      // Copied from GET /audit on the sandbox, field for field.
      final e = AuditEntry.fromJson(const {
        'id': 84,
        'ts': '2026-07-27T23:48:01.722885783Z',
        'actor_type': 'anonymous',
        'actor_id': null,
        'actor_label': 'attempted_username:admin',
        'event_type': 'auth.login',
        'scope_used': null,
        'target_kind': null,
        'target_id': null,
        'correlation_id': null,
        'ip': null,
        'user_agent': null,
        'result': 'denied',
        'detail': null,
      });
      expect(e.denied, isTrue);
      expect(e.eventClass, 'auth');
      expect(e.at.isUtc, isTrue);
      expect(auditActorName(e), 'tried: admin');
      expect(auditPhrase(e), 'Sign-in refused');
    });

    test('an unparseable timestamp keeps the row rather than dropping it', () {
      final e = AuditEntry.fromJson(const {'ts': 'not a date'});
      expect(e.at.millisecondsSinceEpoch, 0);
      expect(e.result, 'success');
    });
  });

  group('auditPhrase', () {
    test('a sign-in reads differently depending on whether it worked', () {
      expect(auditPhrase(_e()), 'Signed in');
      expect(auditPhrase(_e(result: 'denied')), 'Sign-in refused');
    });

    test('names the thing acted on from detail, not the UUID', () {
      final e = _e(
        event: 'user.created',
        targetId: 'fa2640bf-6e60-4a21-be52-70b7ace8e001',
        detail: {'username': 'john', 'role': 'admin'},
      );
      expect(auditPhrase(e), 'Created user “john”');
    });

    test('an API key is named by its label', () {
      final e = _e(
        event: 'api_key.created',
        detail: {
          'label': 'Grafana dashboard',
          'scopes': ['audit:read']
        },
      );
      expect(auditPhrase(e), 'Created API key “Grafana dashboard”');
    });

    test('a config change says which section, never the value', () {
      // Core deliberately records section names only — the values hold
      // passwords. The phrase must not imply it knows more than it does.
      expect(
        auditPhrase(_e(event: 'system.config_updated', detail: {
          'mode': 'patch',
          'sections': ['broker']
        })),
        'Changed configuration [broker]',
      );
      expect(
        auditPhrase(_e(event: 'system.config_updated', detail: {
          'mode': 'patch',
          'sections': ['broker', 'auth', 'logging']
        })),
        'Changed configuration 3 sections',
      );
    });

    test('an event this client has never heard of still reads as English', () {
      // The case that matters: core adds event types without asking the
      // client, and the alternative to a generic reading is a blank cell.
      expect(auditPhrase(_e(event: 'device.deleted')), 'Deleted device');
      expect(auditPhrase(_e(event: 'scene.applied')), 'Applied scene');
    });

    test('an event with no dot does not crash the sentence', () {
      expect(auditPhrase(_e(event: 'startup')), 'Startup');
    });
  });

  group('auditActorName', () {
    test('drops the kind prefix core writes into the label', () {
      // Every real row is `<kind>:<who>` — `user:admin`. The kind is already
      // the row's icon, so printing it again is noise.
      expect(auditActorName(_e(actorLabel: 'user:admin')), 'admin');
      expect(auditActorName(_e(actorLabel: 'api_key:hc-cli')), 'hc-cli');
    });

    test('a blank attempted username says so rather than trailing off', () {
      expect(auditActorName(_e(actorLabel: 'attempted_username:')),
          'tried: (blank)');
    });

    test('falls back to the actor type when there is no label', () {
      expect(auditActorName(_e(actorLabel: '', actorType: 'system')), 'System');
    });
  });

  test('auditClassLabel keeps api_key readable', () {
    expect(auditClassLabel('api_key'), 'API keys');
    expect(auditClassLabel('auth'), 'Sign-ins');
    expect(auditClassLabel('somethingnew'), 'Somethingnew');
  });

  test('auditDetailValue flattens a scope list instead of printing JSON', () {
    expect(auditDetailValue(['audit:read', 'users:read']),
        'audit:read, users:read');
    expect(auditDetailValue(null), '—');
    expect(auditDetailValue(17177892), '17177892');
  });

  group('groupByDay', () {
    test('newest day first, newest entry first inside it', () {
      // Anchored to today's midnight, not to `now` minus a few hours: run this
      // at 02:00 UTC and "three hours ago" is yesterday, which made the first
      // version of this test pass all afternoon and fail overnight.
      final now = DateTime.now().toUtc();
      final midnight = DateTime.utc(now.year, now.month, now.day);
      final days = groupByDay([
        _e(at: midnight.subtract(const Duration(hours: 2))),
        _e(at: midnight.add(const Duration(hours: 9))),
        _e(at: midnight.add(const Duration(hours: 4))),
      ], utc: true);

      expect(days.length, 2);
      expect(days.first.label, startsWith('Today'));
      expect(days[1].label, startsWith('Yesterday'));
      expect(
        days.first.entries.first.at.isAfter(days.first.entries.last.at),
        isTrue,
      );
    });

    test('groups in the timezone being displayed, not always UTC', () {
      // 00:30 UTC is the previous evening in every western timezone. A day
      // heading that disagrees with the timestamps under it is worse than none,
      // so the grouping has to follow the same clock the rows are printed in.
      final at = DateTime.utc(2026, 7, 27, 0, 30);
      final utcDay = groupByDay([_e(at: at)], utc: true).first.label;
      final localDay = groupByDay([_e(at: at)], utc: false).first.label;
      final offset = at.toLocal().day != at.day;
      expect(utcDay == localDay, !offset);
    });

    test('no entries, no day headings', () {
      expect(groupByDay(const [], utc: false), isEmpty);
    });
  });
}
