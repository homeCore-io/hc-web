import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../core/dashboard/code_runtime.dart';

/// An element the browser draws, from code the house's owner wrote.
///
/// The whole security posture is two attributes and one absence:
///
/// * `sandbox="allow-scripts"` **without** `allow-same-origin`. The frame gets
///   an opaque origin, so it cannot read this app's cookies, storage, DOM or
///   session — it is drawn inside the page and is a stranger to it. The two
///   flags together would be worse than no sandbox at all, because a frame with
///   both can reach up and remove its own `sandbox` attribute.
/// * A `Content-Security-Policy` of `default-src 'none'` inside the document,
///   so a pasted card cannot phone home. A srcdoc frame inherits its parent's
///   policy and hc-web ships none, so that meta tag is the only policy there is.
/// * No `allow-*` on anything else: no forms, no popups, no top-navigation, no
///   pointer lock, no downloads.
///
/// What it *can* do is read and act on the devices the element was granted, and
/// nothing else — enforced on this side, in [_onMessage], because a check that
/// lives inside the sandbox is a check the sandbox can delete.
///
/// **Messages are proved by a nonce, not by `event.source`.** Comparing the
/// event's source with `contentWindow` is the obvious check and it is right in
/// JavaScript; across interop it compares extension-type wrappers rather than
/// the windows themselves, and it answered "different" for the same window —
/// which dropped every message including the handshake, so a card drew its
/// starting markup and then never heard from the house again. See [codeNonce].
///
/// **Pointer events are a mode, not a setting.** A platform view is real DOM,
/// so the browser routes clicks to it and Flutter never sees them — the camera
/// view documents this and solves it by never taking any. A code element is a
/// control surface, so it cannot do that; instead the frame is inert while the
/// designer is arranging it, and live when the page is being used or the card
/// has been entered. Without that, a code element would be the one card on the
/// page you could not select or drag.
class CodeElement extends StatefulWidget {
  const CodeElement({
    super.key,
    required this.html,
    required this.cssVars,
    required this.states,
    required this.nonce,
    required this.live,
    this.allowNetwork = false,
    this.assetOrigin,
    this.onSet,
    this.onLog,
  });

  /// The author's markup, dropped into the document body.
  final String html;

  /// The skin, as CSS custom properties.
  final Map<String, String> cssVars;

  /// The `state` message, already encoded. A string because that is what
  /// crosses the boundary, and because it makes "has anything changed?" a
  /// comparison rather than a deep walk of every device on every rebuild.
  final String states;

  /// Proves a message came from this element's own frame. The same value
  /// stamps [states], so the two directions cannot drift apart.
  final String nonce;

  /// Whether the frame may take the pointer.
  final bool live;

  final bool allowNetwork;
  final String? assetOrigin;

  /// A device write the frame asked for, already proved to be within its grant.
  final void Function(String id, Map<String, dynamic> patch)? onSet;

  /// `homecore.log(...)`, and anything the frame threw.
  final ValueChanged<String>? onLog;

  @override
  State<CodeElement> createState() => _CodeElementState();
}

class _CodeElementState extends State<CodeElement> {
  late final String _viewType;
  late final web.HTMLIFrameElement _frame;
  late final JSFunction _listener;

  /// True once the shim has said hello. State sent before that is state the
  /// frame's own listener was not yet registered for, so it would be dropped in
  /// silence and the card would sit at its starting values until something in
  /// the house happened to change.
  bool _ready = false;

  static int _seq = 0;

  @override
  void initState() {
    super.initState();
    _viewType = 'hc-code-${_seq++}';
    _frame = web.HTMLIFrameElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none'
      ..style.display = 'block'
      ..style.background = 'transparent'
      ..setAttribute('sandbox', codeSandbox)
      // Named so a browser's own error messages and dev tools say which card,
      // rather than "<iframe>".
      ..setAttribute('title', 'Code element');
    _frame.style.pointerEvents = widget.live ? 'auto' : 'none';

    _listener = _onMessage.toJS;
    web.window.addEventListener('message', _listener);

    ui_web.platformViewRegistry
        .registerViewFactory(_viewType, (int _) => _frame);
    _write();
  }

  @override
  void didUpdateWidget(covariant CodeElement old) {
    super.didUpdateWidget(old);

    if (old.live != widget.live) {
      _frame.style.pointerEvents = widget.live ? 'auto' : 'none';
    }

    // A rewrite tears the document down and starts it again, so it is reserved
    // for the things that *are* the document. State changes must never do it:
    // a card that reloaded every time a sensor moved would restart its own
    // animations several times a minute.
    if (old.html != widget.html ||
        old.allowNetwork != widget.allowNetwork ||
        old.assetOrigin != widget.assetOrigin ||
        !_sameVars(old.cssVars, widget.cssVars)) {
      _write();
    } else if (old.states != widget.states) {
      _send();
    }
  }

  bool _sameVars(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  void _write() {
    _ready = false;
    _frame.srcdoc = buildCodeDocument(
      html: widget.html,
      cssVars: widget.cssVars,
      allowNetwork: widget.allowNetwork,
      assetOrigin: widget.assetOrigin,
      nonce: widget.nonce,
    ).toJS;
  }

  void _send() {
    if (!_ready) return;
    // `'*'` as the target origin, because the frame's origin is opaque and
    // there is no string that would match it. Safe here in a way it usually is
    // not: the payload is this house's device state going *into* our own
    // sandbox, not a secret going out to a page someone else controls.
    _frame.contentWindow?.postMessage(widget.states.toJS, '*'.toJS);
  }

  void _onMessage(web.MessageEvent event) {
    // No origin check: an opaque-origin frame posts as `"null"`, which anything
    // else can post as too. The nonce is what makes this ours.
    final message = parseCodeMessage(event.data.dartify(), widget.nonce);
    switch (message) {
      case CodeHello():
        _ready = true;
        _send();
      case CodeLog(:final text):
        widget.onLog?.call(text);
      case CodeSet(:final id, :final patch):
        // The grant is enforced here rather than inside the frame, because
        // anything inside the frame is the author's to delete.
        widget.onSet?.call(id, patch);
      case null:
        break;
    }
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    // Blanking the document stops whatever it had running — a timer, an
    // animation, a media element — for a card nobody is looking at any more.
    _frame.srcdoc = ''.toJS;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
