import 'dart:typed_data';

import '../api/assets_api.dart';
import 'sweet_home.dart';

/// Somewhere to put one texture, and what address it got.
///
/// A function rather than the API object, so the rule below can be exercised
/// without a running core — which matters more here than anywhere else in the
/// import, because this is the only step that can fail halfway and the only one
/// whose failures are meant to be survivable.
typedef TextureUploader = Future<String> Function(
  Uint8List bytes, {
  required String filename,
  required String contentType,
  required String group,
});

/// What storing an archive's floor textures came to.
class StoredTextures {
  const StoredTextures({required this.plan, required this.refused, this.total});

  /// The home, with each floor pointing at the asset it reached — and with no
  /// floor at all where it did not.
  final HomePlan plan;

  /// How many textures did not make it. Zero is the ordinary case.
  final int refused;

  /// How many there were to begin with.
  final int? total;

  /// What to say, or null when there is nothing worth saying.
  ///
  /// Deliberately not phrased as a failure. The home imported, the walls are
  /// drawn, the markers are placed; a floor is flat. Someone told "import
  /// failed" here goes looking for a plan that is already on their card.
  String? get note {
    if (refused == 0) return null;
    if (refused == total) {
      return 'The home imported, but none of its textures could be stored — '
          'the floors are drawn plain.';
    }
    return '$refused of $total textures could not be stored; those floors are '
        'drawn plain.';
  }
}

/// Uploads the pictures an imported home's floors name.
///
/// **Nothing here stops the import.** A texture core refuses, one over the size
/// cap, a box that went away mid-upload — each costs one room its floor and
/// nothing else, which is exactly the plan as it was before textures worked at
/// all. Failing the whole import instead would throw away a parsed house over a
/// picture of a carpet.
///
/// One at a time rather than all at once: an archive can name a dozen, each a
/// megabyte, and a browser firing twelve concurrent uploads at a house server
/// is how you turn a slow import into a failed one.
Future<StoredTextures> storeTextures(
  SweetHome home,
  TextureUploader upload, {
  void Function(int done, int total)? onProgress,
}) async {
  final entries = home.textures.entries.toList();
  if (entries.isEmpty) return StoredTextures(plan: home.plan, refused: 0);

  // One group for the archive, named from the bytes — see [SweetHome.group].
  final group = home.group;
  final stored = <String, String>{};
  var refused = 0;

  for (final (index, entry) in entries.indexed) {
    onProgress?.call(index + 1, entries.length);
    // Sniffed, because an archive entry is called `2` and has no extension to
    // go on. Anything core would refuse is skipped here rather than stored
    // under a lie and served as a broken image later.
    final type = sniffImageType(entry.value);
    if (type == null || entry.value.length > maxAssetBytes) {
      refused++;
      continue;
    }
    try {
      stored[entry.key] = await upload(
        entry.value,
        // The archive calls it `2`. Given a name it reads in the manager as one
        // of a plan's textures rather than as a mystery, which is the
        // difference between a group someone will prune and a list nobody
        // dares touch.
        filename: '$group-${entry.key}.${_extension(type)}',
        contentType: type,
        group: group,
      );
    } catch (_) {
      refused++;
    }
  }

  return StoredTextures(
    plan: home.plan.withStoredTextures(stored),
    refused: refused,
    total: entries.length,
  );
}

String _extension(String contentType) => switch (contentType) {
      'image/jpeg' => 'jpg',
      'image/svg+xml' => 'svg',
      _ => contentType.split('/').last,
    };
