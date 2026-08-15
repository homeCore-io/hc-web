/// The document, the contract and the payload for a code element.
///
/// Everything here is pure and has no `dart:ui_web` in it, so the rules that
/// matter — what the sandbox may reach, which devices get in, what a message
/// looks like — are testable without a browser. The widget that mounts an
/// `<iframe>` is [CodeElement]; this is what it puts inside one.
///
/// **Why an element that runs code exists at all.** Twenty card types are
/// compiled into this app, and adding a twenty-first means writing Dart and
/// cutting a release. Home Assistant's button-card is the counter-example: a
/// person builds a triple-arc gauge with glowing SVG in an afternoon, inside
/// the product, without shipping anything. That is the capability this closes,
/// and no arrangement of panels closes it.
///
/// **Why an iframe rather than an SVG renderer.** `flutter_svg` is not a
/// dependency and would not be enough if it were: it does not implement SVG
/// filters, so a `feGaussianBlur` glow — the thing that makes such a gauge look
/// the way it does — renders flat. The browser's own renderer has no such gap,
/// and the app already draws real DOM through `platformViewRegistry` for
/// cameras. This is that mechanism, pointed at a document we compose.
library;

import 'dart:convert';
import 'dart:math';

import '../models/device_state.dart';

/// How the sandbox and the page agree to talk. Sent in every message and
/// checked on the way back, so an older frame left over in a stale tab cannot
/// be mistaken for a current one.
const codeRuntimeVersion = 1;

/// Where the nonce is spliced into [codeShim].
const _noncePlaceholder = '__HC_NONCE__';

/// A secret this element and its frame share, and nobody else can read.
///
/// **This is how a message is proved to have come from our own frame**, and it
/// replaces comparing `event.source` with the iframe's `contentWindow`. That
/// comparison is right in JavaScript and unreliable across the interop
/// boundary — `MessageEventSource` and `Window` are different extension types
/// over `JSObject`, so `==` is answering a question about Dart wrappers rather
/// than about the JS objects underneath, and it silently answered "different"
/// for the same window. Every message was dropped, including the handshake, so
/// a card rendered its starting markup and then never heard about the house
/// again. Under wasm the same comparison would be wrong in a different way.
///
/// A nonce has none of that ambiguity, and it authenticates the *inbound*
/// direction too: the frame ignores state that does not carry its own nonce.
/// It is readable by the author's code inside the frame, which is nothing —
/// that code already holds the element's whole grant. It is not readable by any
/// other origin, because nothing else can see a srcdoc we wrote.
String codeNonce() {
  final random = Random.secure();
  return List.generate(16, (_) => random.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// What a code element may reach.
///
/// **The device grant is the whole permission model.** An element names a
/// selection — ids, a room, a kind, a query — and the sandbox is handed exactly
/// those devices and may act on exactly those devices. An element that names
/// nothing renders and can do nothing, which is the right default for code you
/// pasted from the internet.
///
/// Everything else is closed by the same principle: no network, no storage, no
/// same-origin, no navigation. `allow-scripts` **without** `allow-same-origin`
/// is what makes this safe rather than merely tidy — the frame gets an opaque
/// origin, so it cannot read this app's cookies, storage or DOM even though it
/// is drawn inside the page. The two must never be set together; that
/// combination lets the frame remove its own sandbox attribute.
const codeSandbox = 'allow-scripts';

/// The `Content-Security-Policy` for the document inside the frame.
///
/// A srcdoc frame inherits its parent's policy, and hc-web ships none — so this
/// meta tag is the only policy in force and has to be written as though it were
/// the last line of defence, because it is.
///
/// `default-src 'none'` means a pasted card cannot phone home: no `fetch`, no
/// beacon, no tracking pixel, no font from a CDN. [allowNetwork] opens that
/// deliberately, per element, for the case where reaching something on the LAN
/// is the point.
String codeCsp({required bool allowNetwork, String? assetOrigin}) {
  final img = <String>['data:', 'blob:', if (assetOrigin != null) assetOrigin];
  return [
    "default-src 'none'",
    // Inline only, because the author's code *is* inline. No remote script can
    // be pulled in even with the network open.
    "script-src 'unsafe-inline'",
    "style-src 'unsafe-inline'",
    'img-src ${img.join(' ')}${allowNetwork ? ' https: http:' : ''}',
    'font-src data:',
    if (allowNetwork) 'connect-src https: http:',
  ].join('; ');
}

/// The API the author writes against, injected above their code.
///
/// Deliberately four things. A large API here would be a second product to
/// document and version; these four are what a gauge, a control and a readout
/// need, and they map onto what a button-card author already reaches for.
///
///     homecore.states                  // {id: {name, area, online, state{}}}
///     homecore.onUpdate(fn)            // now, and on every change
///     homecore.set(id, {on: true})     // granted devices only
///     homecore.log(...)                // shows up in the inspector
///
/// Messages are JSON **strings** in both directions rather than structured
/// clones. A string crosses an opaque-origin boundary with no conversion
/// surface at all, which is one less thing to get subtly wrong in a place where
/// getting it wrong means a sandbox escape.
const codeShim = r'''
(function () {
  var NONCE = '__HC_NONCE__';
  var listeners = [];
  var api = {
    version: 1,
    states: {},
    onUpdate: function (fn) {
      if (typeof fn !== 'function') return;
      listeners.push(fn);
      // Called immediately when state has already arrived, so a card written as
      // `homecore.onUpdate(render)` draws on load rather than on the next
      // change — which for a quiet sensor could be an hour.
      if (api.ready) { try { fn(api.states); } catch (e) { api.log('' + e); } }
    },
    set: function (id, patch) {
      send({ type: 'set', id: id, patch: patch });
    },
    log: function () {
      var parts = [];
      for (var i = 0; i < arguments.length; i++) {
        var a = arguments[i];
        parts.push(typeof a === 'string' ? a : JSON.stringify(a));
      }
      send({ type: 'log', text: parts.join(' ') });
    },
    ready: false
  };

  function send(msg) {
    msg.hc = 1;
    msg.n = NONCE;
    parent.postMessage(JSON.stringify(msg), '*');
  }

  window.addEventListener('message', function (event) {
    var msg;
    try { msg = JSON.parse(event.data); } catch (e) { return; }
    if (!msg || msg.hc !== 1 || msg.n !== NONCE || msg.type !== 'state') return;
    api.states = msg.states || {};
    api.ready = true;
    for (var i = 0; i < listeners.length; i++) {
      try { listeners[i](api.states); } catch (e) { api.log('' + e); }
    }
  });

  // An error in pasted code is a blank rectangle otherwise, with no way to find
  // out why. It goes to the inspector instead.
  window.addEventListener('error', function (e) {
    send({ type: 'log', text: 'Error: ' + e.message + ' (line ' + e.lineno + ')' });
  });

  window.homecore = api;
  send({ type: 'hello' });
})();
''';

/// The whole document that goes in the frame.
///
/// [cssVars] is the skin, handed in as custom properties — `--hc-accent`,
/// `--hc-ink`, `--hc-raised` and the rest — so an author can write
/// `var(--hc-accent)` and have their element restyle with the house instead of
/// being a permanent literal. A skin has to reach the whole app, and an element
/// that runs its own code is the easiest place in the product for that promise
/// to quietly stop being true.
///
/// The body is transparent: the element sits on whatever the page's background
/// is, and a card that painted its own ground would be a grey rectangle on a
/// photograph.
String buildCodeDocument({
  required String html,
  required Map<String, String> cssVars,
  required String nonce,
  bool allowNetwork = false,
  String? assetOrigin,
}) {
  final vars = cssVars.entries.map((e) => '  ${e.key}: ${e.value};').join('\n');
  return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="${codeCsp(allowNetwork: allowNetwork, assetOrigin: assetOrigin)}">
<style>
:root {
$vars
}
html, body {
  margin: 0;
  padding: 0;
  width: 100%;
  height: 100%;
  background: transparent;
  color: var(--hc-ink);
  font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
  overflow: hidden;
}
</style>
<script>${codeShim.replaceAll(_noncePlaceholder, nonce)}</script>
</head>
<body>
$html
</body>
</html>
''';
}

/// One device, as the sandbox sees it.
///
/// A narrowed view rather than the whole [DeviceState]: the schema, the plugin
/// id and the override bookkeeping are this app's business, and an API is
/// easier to widen later than to take back. `state` is the attribute map
/// verbatim, because that is the part an author is actually reading.
Map<String, dynamic> codeDeviceView(DeviceState d) => {
      'id': d.id,
      'name': d.displayName,
      'area': d.effectiveArea,
      'type': d.deviceType,
      'online': d.available,
      'state': d.state,
      'last_seen': d.lastSeen.toIso8601String(),
    };

/// The `state` message, as the string that crosses the boundary.
String codeStateMessage(List<DeviceState> granted, String nonce) => jsonEncode({
      'hc': codeRuntimeVersion,
      'n': nonce,
      'type': 'state',
      'states': {for (final d in granted) d.id: codeDeviceView(d)},
    });

/// A message from the frame, once it has been proved to be one.
///
/// Returns null for anything that is not a well-formed message from *this*
/// element's frame — which includes every message from every other frame,
/// extension and library that shares this window. Nothing downstream gets to
/// assume shape, and nothing without [nonce] gets in at all.
CodeMessage? parseCodeMessage(Object? data, String nonce) {
  if (data is! String) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(data);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  if (decoded['hc'] != codeRuntimeVersion) return null;
  // The sender check. Every other frame, extension and library on this window
  // posts messages too, and none of them can know this.
  if (decoded['n'] != nonce) return null;
  final type = decoded['type'];
  if (type is! String) return null;
  return switch (type) {
    'hello' => const CodeMessage.hello(),
    'log' => CodeMessage.log('${decoded['text'] ?? ''}'),
    'set' => switch ((decoded['id'], decoded['patch'])) {
        (final String id, final Map patch) when id.isNotEmpty =>
          CodeMessage.set(id, Map<String, dynamic>.from(patch)),
        _ => null,
      },
    _ => null,
  };
}

/// What the frame can say back.
sealed class CodeMessage {
  const CodeMessage();

  /// The shim is up and listening, so the first state can be sent.
  const factory CodeMessage.hello() = CodeHello;
  const factory CodeMessage.log(String text) = CodeLog;
  const factory CodeMessage.set(String id, Map<String, dynamic> patch) =
      CodeSet;
}

class CodeHello extends CodeMessage {
  const CodeHello();
}

class CodeLog extends CodeMessage {
  const CodeLog(this.text);
  final String text;
}

class CodeSet extends CodeMessage {
  const CodeSet(this.id, this.patch);
  final String id;
  final Map<String, dynamic> patch;
}

/// What a new code element starts life as.
///
/// Not an empty string: an empty frame is indistinguishable from a broken one,
/// and the first question a blank code element raises is "what is the API?".
/// Answering it in the element itself costs nothing and is read at exactly the
/// moment it is wanted.
const codeStarter = '''
<style>
  .box {
    display: grid; place-content: center; gap: 6px;
    height: 100%; text-align: center;
    font: 500 13px/1.4 system-ui, sans-serif;
  }
  .value { font-size: 40px; font-weight: 200; color: var(--hc-accent); }
  .label { font-size: 10px; letter-spacing: .18em; text-transform: uppercase;
           color: var(--hc-muted); }
</style>
<div class="box">
  <div class="value" id="value">--</div>
  <div class="label" id="label">no devices granted</div>
</div>
<script>
  homecore.onUpdate(function (states) {
    var first = Object.values(states)[0];
    if (!first) return;
    document.getElementById('label').textContent = first.name;
    var v = first.state.temperature ?? first.state.value ?? first.state.on;
    document.getElementById('value').textContent = String(v ?? '--');
  });
</script>
''';
