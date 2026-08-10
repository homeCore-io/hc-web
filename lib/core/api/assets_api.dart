import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'homecore_client.dart';

/// Somewhere to put a picture.
///
/// Core stores blobs content-addressed: the id is the sha256 of the bytes, so
/// uploading the same file twice yields one asset and the address can never
/// describe different bytes later. That is also why [assetUrl] is safe to hand
/// to `Image.network` and to the font registry without a token — the read is
/// public precisely because the id is unguessable.
class AssetsApi {
  AssetsApi(this.client);
  final HomecoreClient client;

  /// Stores [bytes] and returns the address to keep.
  ///
  /// [group] ties an upload to whatever it arrived with — a floor plan import
  /// names its own group so its textures can be pruned together later.
  Future<AssetRef> upload(
    Uint8List bytes, {
    required String filename,
    required String contentType,
    String? group,
  }) async {
    final res = await client.dio.post<Map<String, dynamic>>(
      '/assets',
      // The bytes themselves, not a stream of them. They arrived whole from a
      // FileReader, so there is nothing to stream, and dio sets the length
      // itself rather than being told. (Both shapes were checked against a
      // running core; this is the one with fewer moving parts.)
      data: bytes,
      queryParameters: {
        'name': filename,
        if (group != null) 'group': group,
      },
      options: Options(headers: {Headers.contentTypeHeader: contentType}),
    );
    return AssetRef.fromJson(res.data ?? const {});
  }

  Future<List<AssetRef>> list() async {
    final res = await client.dio.get<Map<String, dynamic>>('/assets');
    final raw = (res.data?['assets'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((m) => AssetRef.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  Future<void> delete(String id) => client.dio.delete('/assets/$id');

  Future<int> deleteGroup(String group) async {
    final res =
        await client.dio.delete<Map<String, dynamic>>('/assets/group/$group');
    return (res.data?['deleted'] as num?)?.toInt() ?? 0;
  }
}

/// What core stored, and where it lives.
class AssetRef {
  const AssetRef({
    required this.id,
    required this.contentType,
    required this.size,
    required this.name,
    this.group,
  });

  factory AssetRef.fromJson(Map<String, dynamic> json) => AssetRef(
        id: json['id'] as String? ?? '',
        contentType: json['content_type'] as String? ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        group: json['group'] as String?,
      );

  final String id;
  final String contentType;
  final int size;
  final String name;
  final String? group;

  /// The address to store in a dashboard or a skin.
  String get url => assetUrl(id);
}

/// Relative on purpose.
///
/// It resolves against whatever origin the app is served from, so the same
/// stored string works on the LAN, through nginx and over remote access —
/// which an absolute address baked in at upload time would not.
String assetUrl(String id) => '/api/v1/assets/$id';

/// Whether an address points at core's own asset store.
bool isAssetUrl(String url) =>
    RegExp(r'^/api/v1/assets/[0-9a-f]{64}$').hasMatch(url.trim());

/// What core will accept, keyed by the extension people actually have.
///
/// Declared by the uploader and never sniffed, which means getting this wrong
/// is a 415 rather than a file stored under a lie.
const assetContentTypes = <String, String>{
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'avif': 'image/avif',
  'svg': 'image/svg+xml',
  'ttf': 'font/ttf',
  'otf': 'font/otf',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
};

/// The `accept` string for a file input, for the kinds in [extensions].
String acceptFor(Iterable<String> extensions) =>
    extensions.map((e) => '.$e').join(',');

/// Everything core stores as a picture.
const imageExtensions = ['png', 'jpg', 'jpeg', 'webp', 'gif', 'avif', 'svg'];

/// Everything core stores as a font.
const fontExtensions = ['ttf', 'otf', 'woff', 'woff2'];

/// The content type for [filename], or null if core would refuse it.
String? contentTypeFor(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return null;
  return assetContentTypes[filename.substring(dot + 1).toLowerCase()];
}

/// Core's own per-asset cap, so the picker can say no before the round trip.
const maxAssetBytes = 16 * 1024 * 1024;

/// A size someone can read.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
