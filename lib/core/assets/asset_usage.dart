import 'dart:convert';

import '../api/assets_api.dart';
import '../models/dashboard.dart';
import '../models/skin_document.dart';

/// Who is still pointing at an asset.
///
/// Core does not reference-count, deliberately: counting is the half that
/// deletes something still in use the moment the count is wrong, and a house
/// that loses a wallpaper because a page was mid-save has traded a small
/// nuisance for a real one. So nothing is ever removed automatically, and this
/// answers the question the manager actually needs — *what would I break?* —
/// at the moment someone is looking, rather than continuously.
///
/// It is computed by searching what the client already holds. An asset is
/// referenced by its **address**, and an address embeds the id, so a text
/// search over the serialised document finds every one: a card's picture, a
/// page background, an image widget's config, a skin's font. No schema
/// knowledge, and nothing to update when a fifth place learns to store one —
/// which is the point, because the first four were each added separately and
/// each was written up as if it were the only one.
class AssetUsage {
  const AssetUsage(this.dashboards, this.skins);

  /// Names of the dashboards that reference it.
  final List<String> dashboards;

  /// Names of the skins that reference it.
  final List<String> skins;

  bool get isEmpty => dashboards.isEmpty && skins.isEmpty;
  int get count => dashboards.length + skins.length;

  /// What to show beside the asset. Null when nothing uses it.
  String? get summary {
    if (isEmpty) return null;
    final parts = [...dashboards, ...skins];
    if (parts.length <= 2) return 'Used by ${parts.join(' and ')}';
    return 'Used by ${parts.take(2).join(', ')} and ${parts.length - 2} more';
  }
}

/// Which assets are referenced by what, in one pass.
///
/// One pass over the documents rather than one per asset: a house with forty
/// floor plan textures and a dozen dashboards would otherwise be five hundred
/// searches to draw one page.
Map<String, AssetUsage> assetUsage({
  required Iterable<AssetRef> assets,
  required Iterable<DashboardDefinition> dashboards,
  required Iterable<SkinDocument> skins,
}) {
  final dashboardText = {
    for (final d in dashboards) d.name: jsonEncode(d.toJson()),
  };
  final skinText = {
    for (final s in skins) s.name: jsonEncode(s.toJson()),
  };

  return {
    for (final asset in assets)
      asset.id: AssetUsage(
        [
          for (final e in dashboardText.entries)
            if (e.value.contains(asset.id)) e.key,
        ],
        [
          for (final e in skinText.entries)
            if (e.value.contains(asset.id)) e.key,
        ],
      ),
  };
}
