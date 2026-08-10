import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/assets_api.dart';
import 'auth_provider.dart';

/// Core's blob store.
final assetsApiProvider = Provider<AssetsApi>((ref) {
  return AssetsApi(ref.watch(homecoreClientProvider));
});

/// Everything stored, newest first.
///
/// Only the manager needs this — the picker uploads and keeps the address it
/// gets back, so it never has to enumerate. That is deliberate: the listing is
/// authenticated because it is the one call that would turn an unguessable
/// asset id into a guessable one.
final assetListProvider = FutureProvider<List<AssetRef>>((ref) async {
  return ref.watch(assetsApiProvider).list();
});
