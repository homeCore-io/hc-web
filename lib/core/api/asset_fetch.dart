import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../design/font_registry.dart';

/// Bytes for a file the browser can reach.
///
/// [FontRegistry] is handed its fetcher rather than owning one, so that tests
/// never reach the network. That was right, and it was also the whole bug: the
/// hook defaulted to a stub returning `null` and **nothing outside the tests
/// ever replaced it**, so `register` always answered `false` and a custom font
/// never loaded. The fonts UI shipped in 0.1.36 against a fetcher that could
/// not fetch.
///
/// The fix is a real implementation plus one line in `main.dart`. It is wired
/// there and not in `app.dart` on purpose: widget tests build `HomecoreApp`
/// directly and would otherwise start pulling font files over the network
/// mid-test — the same trap `Image.network` set in the page-background tests,
/// where a failure landed asynchronously on whichever test happened to be
/// running.
///
/// Not the authenticated client's `Dio`: a font lives wherever the house put
/// it, which is not the API's base URL, and it needs no token to read.

final _dio = Dio(BaseOptions(
  responseType: ResponseType.bytes,
  // A font is a few hundred kilobytes on the LAN. These exist so a dead
  // address costs a typeface and a short wait rather than hanging.
  connectTimeout: const Duration(seconds: 8),
  receiveTimeout: const Duration(seconds: 20),
  // We judge the status ourselves; a 404 is an answer, not an exception.
  validateStatus: (_) => true,
));

/// Fetches [url], or null if it cannot be read.
///
/// Never throws. A font that will not load costs you a typeface, not a house —
/// the same contract [FontRegistry.register] already keeps.
Future<Uint8List?> fetchAssetBytes(String url) async {
  final uri = resolveAssetUrl(url);
  if (uri == null) return null;
  // http(s) only. A skin override is authored text, and the house is the thing
  // that should be serving its own fonts — `data:` would bloat the document
  // and `file:` would mean nothing to a browser.
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  try {
    final res = await _dio.getUri<List<int>>(uri);
    final data = res.data;
    if (res.statusCode != 200 || data == null || data.isEmpty) return null;
    return Uint8List.fromList(data);
  } catch (_) {
    return null;
  }
}

/// Resolves what a skin stored into something fetchable.
///
/// Absolute addresses are used as written. A relative one resolves against the
/// page — which is what makes this survive §7.11: on the day core can store an
/// asset, the same field takes `/assets/…` and nothing else changes.
Uri? resolveAssetUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  return uri.hasScheme ? uri : Uri.base.resolve(trimmed);
}

/// Gives the font registry a fetcher that fetches.
///
/// Called from `main`, which is the app's composition root and the one place a
/// test does not go through.
void installAssetFetch() {
  FontRegistry.instance.fetch = fetchAssetBytes;
}
