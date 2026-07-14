import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'camera_source.dart';

/// A live camera, rendered by the browser rather than by Flutter.
///
/// This is not a stylistic choice, it is the only thing that works. Flutter web
/// draws through CanvasKit, so `Image.network` has to fetch bytes with XHR to
/// decode them into the canvas — CORS applies, and go2rtc sends no
/// `Access-Control-Allow-Origin` header. Every frame would fail while the camera
/// is healthy. A browser's own `<img>`/`<video>` has no such problem: the
/// same-origin rule protects *reading* pixels, not *displaying* them.
///
/// For a go2rtc source it mounts go2rtc's own `<video-stream>` element (vendored
/// in web/vendor/go2rtc/), which negotiates WebRTC → MSE → MJPEG over a
/// WebSocket. If that socket is refused — the common case, because go2rtc blocks
/// cross-origin WebSockets by default — it falls back on its own to a plain
/// `<img>` MJPEG, which needs no server config. So the wall works out of the box
/// and gets sharper and lower-latency if you set `api.origin` on the NVR.
///
/// No server-side proxy, and deliberately no server-side URL fetcher — that
/// would be an SSRF gadget pointed at the home network by anyone who could write
/// a dashboard.
class CameraView extends StatefulWidget {
  const CameraView({
    super.key,
    required this.url,
    required this.sourceType,
    this.refreshSecs,
    this.onTransport,
  });

  /// For go2rtc: `http://host:1984/api/ws?src=driveway` (http→ws is handled).
  /// For mjpeg/still: the image URL.
  final String url;

  final String sourceType;

  /// `image_refresh` only.
  final int? refreshSecs;

  /// Reports which transport actually carried the picture, once known — so a
  /// tile can badge "RTC" vs "MJPEG". `null` means still connecting.
  final ValueChanged<String?>? onTransport;

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  late final String _viewType;
  late final web.HTMLDivElement _host;
  late final CameraTransport _transport;

  Timer? _tick;
  Timer? _watchdog;
  int _frame = 0;
  bool _fellBack = false;

  static int _seq = 0;

  @override
  void initState() {
    super.initState();
    _transport = transportFor(widget.sourceType);

    _viewType = 'hc-camera-${_seq++}';
    // A container we own, so we can swap what is inside it — a <video-stream>
    // for its <img> MJPEG fallback — without re-registering the platform view.
    _host = web.HTMLDivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.background = '#05070A';

    ui_web.platformViewRegistry
        .registerViewFactory(_viewType, (int _) => _host);

    _mount();
  }

  void _mount() {
    if (_transport == CameraTransport.go2rtc) {
      _mountVideoStream();
    } else {
      _mountImage(widget.url, _transport);
    }
  }

  void _mountVideoStream() {
    final el = web.document.createElement('video-stream') as web.HTMLElement;
    el.style
      ..width = '100%'
      ..height = '100%'
      ..display = 'block';
    // HLS is dropped — 6-20s of latency is the wrong tool for a live wall.
    el.setJsProperty('mode', 'webrtc,mse,mjpeg');
    el.setJsProperty('background', false);
    el.setJsProperty('src', widget.url);

    _empty(_host);
    _host.append(el);

    // go2rtc's element retries a refused socket forever rather than giving up,
    // so "no picture yet" is the only reliable failure signal. If nothing is
    // playing after a few seconds, drop to the MJPEG <img>, which does not go
    // through the Origin-checked WebSocket and therefore just works.
    _watchdog = Timer(const Duration(seconds: 5), () {
      final video = el.querySelector('video');
      final playing =
          video != null && (video.getJsProperty('videoWidth') as num? ?? 0) > 0;
      if (playing) {
        final mode = el.querySelector('.mode')?.textContent;
        widget.onTransport?.call(mode == null || mode.isEmpty ? 'live' : mode);
      } else {
        _fallBackToMjpeg();
      }
    });
  }

  void _fallBackToMjpeg() {
    if (_fellBack) return;
    _fellBack = true;

    final mjpeg = go2rtcMjpegFallback(widget.url);
    if (mjpeg == null) {
      widget.onTransport?.call('unreachable');
      return;
    }
    _mountImage(mjpeg, CameraTransport.mjpeg);
    widget.onTransport?.call('MJPEG');
  }

  void _mountImage(String url, CameraTransport transport) {
    _tick?.cancel();

    final img = web.HTMLImageElement()
      ..style.width = '100%'
      ..style.height = '100%'
      // The frame decides the aspect; the camera fills it. `contain` would
      // letterbox a security wall into uselessness.
      ..style.objectFit = 'cover'
      ..style.display = 'block';
    img.onLoad.listen((_) => widget.onTransport
        ?.call(transport == CameraTransport.imageRefresh ? 'still' : 'MJPEG'));
    img.onError.listen((_) => widget.onTransport?.call('unreachable'));

    img.src = cameraSrc(url, _sourceTypeFor(transport), _frame);
    _empty(_host);
    _host.append(img);

    if (transport != CameraTransport.imageRefresh) return;

    // A still must be re-fetched, and browsers cache stills hard. Without the
    // buster the same frame is served forever and a live camera looks frozen —
    // the worst failure a security wall can have, because a frozen picture of a
    // quiet driveway is indistinguishable from a quiet driveway.
    final secs = (widget.refreshSecs ?? 2).clamp(1, 300);
    _tick = Timer.periodic(Duration(seconds: secs), (_) {
      _frame++;
      img.src = cameraSrc(url, 'image_refresh', _frame);
    });
  }

  static String _sourceTypeFor(CameraTransport t) =>
      t == CameraTransport.imageRefresh ? 'image_refresh' : 'mjpeg';

  @override
  void dispose() {
    _tick?.cancel();
    _watchdog?.cancel();
    // Drop connections for a camera nobody is looking at. An MJPEG stream is a
    // request that never completes; a WebRTC peer holds a socket open. Browsers
    // allow only a handful per host, so leaks would eventually starve new ones.
    // Emptying the host removes the <video-stream> (it tears down its own
    // socket) and the <img>.
    _empty(_host);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}

extension on web.HTMLElement {
  void setJsProperty(String name, Object? value) =>
      (this as JSObject).setProperty(name.toJS, value?.jsify());
}

/// Removes every child of [el]. `replaceChildren()` in package:web requires at
/// least one argument, so clearing needs a loop.
void _empty(web.Element el) {
  while (el.firstChild != null) {
    el.removeChild(el.firstChild!);
  }
}

extension on web.Element {
  Object? getJsProperty(String name) =>
      (this as JSObject).getProperty(name.toJS).dartify();
}

/// Everything is renderable now — go2rtc handles the streaming transports, an
/// `<img>` handles the rest — but the hook stays so a future unknown type can
/// decline rather than show a black rectangle.
bool cameraRenderable(String sourceType) => true;
