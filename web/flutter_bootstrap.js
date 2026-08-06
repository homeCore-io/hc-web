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

// Glyph fallback goes the same way, for the same reason.
//
// Bundling Inter and JetBrains Mono covers the text this app writes, but not a
// codepoint neither face carries — a device name a plugin reports in a script
// we do not ship, say. CanvasKit's answer is to fetch a fallback font at
// runtime, and its default base is `https://fonts.gstatic.com/s/`.
//
// Nothing is served from `assets/fonts/fallback/` today, so such a glyph
// renders as tofu: visibly missing, which is the honest outcome and sits better
// with "stale is a state, and it must be visible" than a glyph that silently
// depends on the internet. Drop Noto subsets in that directory if real coverage
// is ever wanted — this already points at them.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
    fontFallbackBaseUrl: "assets/fonts/fallback/",
  },
});
