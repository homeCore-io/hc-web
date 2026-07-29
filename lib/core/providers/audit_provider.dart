import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/audit_api.dart';
import 'auth_provider.dart';

final auditApiProvider = Provider<AuditApi>((ref) {
  return AuditApi(ref.watch(homecoreClientProvider));
});

/// The audit trail, and the filter it was fetched under.
///
/// An `AsyncNotifier` rather than a `FutureProvider.family` keyed on the
/// filter, and rather than a Future owned by the page. Both of those were
/// tried and both left the page on its spinner forever:
///
/// - the family's key contains a time bound, so a key rebuilt during `build`
///   differs by a microsecond and asks for a *different* provider, disposing
///   the request in flight;
/// - a page-owned `late Future` started from the first build races app
///   startup on a cold deep link — the reply to that first request never
///   arrived, and the page sat there until you pressed Refresh.
///
/// This is the shape every other admin screen already uses (see
/// `usersProvider`), which is the shape that survives a cold `/admin/...`
/// deep link.
class AuditNotifier extends AsyncNotifier<List<AuditEntry>> {
  AuditFilter _filter = AuditFilter(from: defaultSince(), limit: 500);

  /// What the current data was fetched under — the page reads this rather than
  /// keeping its own copy, so the chips can never disagree with the rows.
  AuditFilter get filter => _filter;

  @override
  Future<List<AuditEntry>> build() => ref.read(auditApiProvider).list(_filter);

  /// Re-query. Only the server-side parts of a filter belong here: `result`
  /// and the time bound. Event class and free text are applied to what came
  /// back, because core matches `event_type` exactly.
  Future<void> apply(AuditFilter next) async {
    _filter = next;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(auditApiProvider).list(next));
  }

  Future<void> reload() => apply(_filter);
}

final auditProvider =
    AsyncNotifierProvider<AuditNotifier, List<AuditEntry>>(AuditNotifier.new);

/// The default lower bound: seven days, truncated to the minute.
///
/// Truncated because a bound that moves every microsecond makes every
/// otherwise-identical query a different query.
DateTime defaultSince() {
  final t = DateTime.now().toUtc().subtract(const Duration(days: 7));
  return DateTime.utc(t.year, t.month, t.day, t.hour, t.minute);
}
