import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/audit_api.dart';
import 'auth_provider.dart';

final auditApiProvider = Provider<AuditApi>((ref) {
  return AuditApi(ref.watch(homecoreClientProvider));
});

/// The audit trail under one set of filters.
///
/// Keyed on the filter so switching "denied only" on and off does not refetch
/// what it already holds, and `autoDispose` so leaving the page drops it —
/// 250 rows of anything is not worth keeping warm.
final auditProvider =
    FutureProvider.family.autoDispose<List<AuditEntry>, AuditQueryKey>(
  (ref, key) => ref.watch(auditApiProvider).list(key.filter),
);

/// A value-equal wrapper so the family can key on a filter.
///
/// [AuditFilter] is a plain class; without this each rebuild would construct a
/// new instance, miss the cache and refetch on every frame.
class AuditQueryKey {
  const AuditQueryKey(this.filter);
  final AuditFilter filter;

  String get _id => [
        filter.actorType,
        filter.eventType,
        filter.targetKind,
        filter.targetId,
        filter.result,
        filter.from?.toIso8601String(),
        filter.to?.toIso8601String(),
        filter.limit,
        filter.offset,
      ].join('|');

  @override
  bool operator ==(Object other) => other is AuditQueryKey && other._id == _id;

  @override
  int get hashCode => _id.hashCode;
}
