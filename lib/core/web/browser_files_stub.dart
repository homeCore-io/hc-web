import 'dart:typed_data';

import 'browser_files_types.dart';

/// Off the web there is nowhere to put a file and nobody to ask for one.
///
/// Both are silent rather than throwing. A test that renders the settings page
/// should not have to avoid the download button, and a stub that threw would
/// turn "this widget builds" into "this widget builds and nobody pressed
/// anything".
void downloadBytes(
  Uint8List bytes,
  String filename, {
  String mime = 'application/octet-stream',
}) {}

/// Null is already the "nothing was chosen" answer, so callers handle it.
Future<PickedFile?> pickFile({String accept = ''}) async => null;
