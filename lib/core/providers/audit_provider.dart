import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/audit_api.dart';
import 'auth_provider.dart';

final auditApiProvider = Provider<AuditApi>((ref) {
  return AuditApi(ref.watch(homecoreClientProvider));
});

// Deliberately no `FutureProvider.family` over the filter.
//
// The first version keyed an autoDispose family on the filter, and the page
// never left its spinner: the key is only as stable as the object that builds
// it, one field of that filter is a time bound, and a key that differs by a
// microsecond is a different provider — disposed and restarted before it can
// finish. A page-owned Future has none of that surface: it is created when a
// server-side filter actually changes, and at no other time. See AuditPage.
