import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Getting bytes out of, and into, the browser.
///
/// hc-web is a web app and nothing else, so this talks to the DOM through
/// `package:web` — already a dependency, already used by the camera views —
/// rather than pulling in a plugin abstracting over platforms this app has not
/// got.

/// Hand the user a file.
///
/// A browser has no "save": you make a blob, point an anchor at it, click it
/// yourself, then release the URL. Releasing matters here — an object URL that
/// is never revoked keeps the whole blob alive for the life of the tab, and a
/// backup of this house is a quarter of a gigabyte.
void downloadBytes(
  Uint8List bytes,
  String filename, {
  String mime = 'application/octet-stream',
}) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

/// A file the user chose.
class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Ask for a file.
///
/// Resolves to null when nothing is chosen. A dismissed picker fires no event
/// at all in most browsers, so this future simply never completes in that case
/// — callers must not block anything irreversible on it.
Future<PickedFile?> pickFile({String accept = ''}) {
  final completer = Completer<PickedFile?>();
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = accept;

  void finish(PickedFile? file) {
    if (!completer.isCompleted) completer.complete(file);
  }

  input.onchange = (web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      finish(null);
      return;
    }
    final file = files.item(0)!;
    final reader = web.FileReader();
    reader.onload = (web.ProgressEvent _) {
      final result = reader.result;
      if (result == null) {
        finish(null);
        return;
      }
      finish(PickedFile(
          file.name, (result as JSArrayBuffer).toDart.asUint8List()));
    }.toJS;
    reader.onerror = (web.ProgressEvent _) {
      finish(null);
    }.toJS;
    reader.readAsArrayBuffer(file);
  }.toJS;

  input.click();
  return completer.future;
}
