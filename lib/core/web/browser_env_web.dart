import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// The browser's address bar and tab handling.
///
/// Two call sites wanted three lines of `package:web` between them — the wall
/// panel's shareable link, and the plugin descriptor's documentation links.
/// Importing the whole DOM into both files to get them is what made
/// `lib/app.dart` unimportable outside a browser.
String get pageOrigin => web.window.location.origin;

String get pageHostname => web.window.location.hostname;

void openInNewTab(String url) => web.window.open(url, '_blank');

/// Whether the browser should ask before closing the tab.
///
/// **A draft lives in the tab.** The designer batches every edit and writes
/// them in one go, which is what makes arranging a page feel like arranging
/// something rather than filing a form — and it means a refresh or a closed
/// tab takes the lot. Cancel and the back arrow ask; the browser's own X did
/// not. John: *"yes add a leave site warning too."*
///
/// The wording is the browser's, not ours: every engine ignores a custom
/// string and shows its own sentence. All we can say is *there is something to
/// lose*, by cancelling the event and leaving `returnValue` non-empty.
void warnBeforeLeaving(bool unsaved) {
  if (unsaved == _guarded) return;
  _guarded = unsaved;
  if (unsaved) {
    web.window.addEventListener('beforeunload', _onBeforeUnload);
  } else {
    web.window.removeEventListener('beforeunload', _onBeforeUnload);
  }
}

bool _guarded = false;

final _onBeforeUnload = ((web.Event event) {
  event.preventDefault();
  (event as web.BeforeUnloadEvent).returnValue = 'unsaved';
}).toJS;
