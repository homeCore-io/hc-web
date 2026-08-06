{{flutter_js}}
{{flutter_build_config}}

// Load the engine from our own origin, not Google's.
//
// `flutter build web` puts CanvasKit in `build/web/canvaskit/` — and then the
// default loader ignores it and fetches
// `https://www.gstatic.com/flutter-canvaskit/<hash>/chromium/canvaskit.wasm`
// instead. Seven megabytes from Google before the app draws anything, from a
// console whose stated scope is working with no route out of the house.
//
// It has been that way since the first build. Nothing surfaced it: any machine
// that can reach the house can usually also reach the internet, so it never
// failed where anyone was watching, and the local copy shipping inside the
// image made it look handled. A house with its internet down got a blank page —
// not a degraded one, a blank one, because the engine never arrived.
//
// Found by measuring the page's requests rather than assuming, while checking
// something else entirely.
//
// This file exists only to pass that config. Deleting it does not fail a build
// or a test — Flutter quietly regenerates the default and the fetch goes back
// to gstatic — so there is a test that asserts it is still here and still
// points at us.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
