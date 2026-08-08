import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/skins_api.dart';
import '../models/skin_document.dart';
import 'auth_provider.dart';

final skinsApiProvider = Provider<SkinsApi>((ref) {
  return SkinsApi(ref.watch(homecoreClientProvider));
});

/// The house's user-defined skins.
///
/// **An empty list is the answer to every failure.** A core too old to have
/// `/skins` answers 404, one without the store configured answers 501, and an
/// unreachable one answers nothing — and the app's response to all three is
/// identical: wear a built-in. Surfacing an error state here would give every
/// consumer a second case to handle for no decision they could make
/// differently.
class SkinsNotifier extends AsyncNotifier<List<SkinDocument>> {
  @override
  Future<List<SkinDocument>> build() async {
    try {
      return await ref.read(skinsApiProvider).listSkins();
    } catch (_) {
      return const [];
    }
  }

  Future<void> reload() async {
    state = AsyncData(await build());
  }
}

final skinsProvider =
    AsyncNotifierProvider<SkinsNotifier, List<SkinDocument>>(SkinsNotifier.new);
