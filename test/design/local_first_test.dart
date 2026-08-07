import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app has to start with no route out of the house.
///
/// Brief §5: *"Does not depend on the public internet or any cloud service —
/// the app is same-origin with core on the LAN and must stay fully useful with
/// no route out of the house."*
///
/// That was not true. The default Flutter web loader ignores the CanvasKit that
/// `flutter build web` writes into `build/web/canvaskit/` and fetches 7MB of
/// wasm from `www.gstatic.com` instead — before the app draws anything. A house
/// with its internet down got a blank page.
///
/// `web/flutter_bootstrap.js` is the only thing holding that shut, and it is a
/// file Flutter will silently regenerate from its own template if it goes
/// missing. Losing it fails no build and no other test, and shows nothing on
/// any screen anyone looks at — the app keeps working everywhere it is normally
/// tried, because the machines it is tried on can reach Google. Hence this.
void main() {
  test('the engine loads from our own origin', () {
    final boot = File('web/flutter_bootstrap.js');
    expect(boot.existsSync(), isTrue,
        reason: 'the bootstrap override is gone; Flutter will regenerate the '
            'default and the engine goes back to being fetched from gstatic');

    final src = boot.readAsStringSync();

    // Match the configured value, not the file's text: the comment above it
    // names the gstatic default in order to explain it, so a naive
    // `isNot(contains("gstatic"))` would fail on the explanation rather than on
    // the thing it warns about.
    final m =
        RegExp(r'''canvasKitBaseUrl:\s*["']([^"']*)["']''').firstMatch(src);
    expect(m, isNotNull, reason: 'canvasKitBaseUrl is not configured');
    expect(m!.group(1)!, isNot(contains('://')),
        reason: 'the engine is fetched off our own origin: ${m.group(1)}');

    // The placeholders are what make this a template rather than a stale copy
    // of one Flutter version's loader.
    expect(src, contains('{{flutter_js}}'));
    expect(src, contains('{{flutter_build_config}}'));
  });
}
