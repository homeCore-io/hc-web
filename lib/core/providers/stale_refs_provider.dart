import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

/// Rules pointing at devices that are gone.
///
/// A quiet failure: the rule fires and does nothing, every time. Nothing else
/// in the app surfaces it, which is why both Maintenance and Manage's attention
/// band read it — from here, so there is one definition rather than a page
/// exporting a provider to another feature.
final staleRefsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(homecoreClientProvider);
  final res = await client.dio.get('/automations/stale-refs');
  return [
    for (final r in (res.data as List)) Map<String, dynamic>.from(r as Map),
  ];
});
