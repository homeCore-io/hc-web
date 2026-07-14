import 'dart:async';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'camera_source.dart';

/// A live camera, rendered by the browser rather than by Flutter.
///
/// Flutter web draws through CanvasKit, so `Image.network` decodes via XHR, so
/// CORS applies — and go2rtc sends no CORS header, so every frame would fail
/// while the camera is healthy. A browser's own element has no such problem: the
/// same-origin rule protects *reading* pixels, not *displaying* them.
///
/// A go2rtc camera is shown by embedding go2rtc's own `stream.html` in an
/// `<iframe>`. That page runs at go2rtc's OWN origin, so its WebSocket back to
/// go2rtc is same-origin and negotiates WebRTC with no `api.origin` config —
/// which is exactly why the same stream opens fine in a browser tab but a
/// `<video-stream>` element hosted in *our* page gets a 403 (its socket is
/// cross-origin). Letting go2rtc host its own player is the whole trick.
///
/// A plain MJPEG or still camera has no such page, so it mounts an `<img>`.
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
    this.onError,
  });

  final String url;
  final String sourceType;

  /// `image_refresh` only.
  final int? refreshSecs;

  /// Fired when an `<img>` source fails to load. The iframe path is opaque
  /// (cross-origin), so failures there are shown by go2rtc inside the frame.
  final VoidCallback? onError;

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  late final String _viewType;
  late final web.HTMLElement _element;
  late final CameraTransport _transport;
  Timer? _tick;
  int _frame = 0;

  static int _seq = 0;

  @override
  void initState() {
    super.initState();
    _transport = transportFor(widget.sourceType);
    _viewType = 'hc-camera-${_seq++}';
    _element = _transport == CameraTransport.go2rtc ? _iframe() : _image();

    ui_web.platformViewRegistry
        .registerViewFactory(_viewType, (int _) => _element);

    _load();
  }

  web.HTMLIFrameElement _iframe() => web.HTMLIFrameElement()
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.border = 'none'
    ..style.display = 'block'
    // WebRTC autoplays muted video; without this some browsers block it.
    ..allow = 'autoplay; fullscreen; picture-in-picture';

  web.HTMLImageElement _image() {
    final img = web.HTMLImageElement()
      ..style.width = '100%'
      ..style.height = '100%'
      // The frame decides the aspect; the camera fills it. `contain` would
      // letterbox a security wall into uselessness.
      ..style.objectFit = 'cover'
      ..style.display = 'block';
    img.onError.listen((_) => widget.onError?.call());
    return img;
  }

  @override
  void didUpdateWidget(covariant CameraView old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url ||
        old.sourceType != widget.sourceType ||
        old.refreshSecs != widget.refreshSecs) {
      _load();
    }
  }

  void _load() {
    _tick?.cancel();

    if (_transport == CameraTransport.go2rtc) {
      (_element as web.HTMLIFrameElement).src = go2rtcEmbedUrl(widget.url);
      return;
    }

    final img = _element as web.HTMLImageElement;
    img.src = cameraSrc(widget.url, widget.sourceType, _frame);

    if (_transport != CameraTransport.imageRefresh) return;

    final secs = (widget.refreshSecs ?? 2).clamp(1, 300);
    _tick = Timer.periodic(Duration(seconds: secs), (_) {
      _frame++;
      img.src = cameraSrc(widget.url, 'image_refresh', _frame);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    // Drop the connection for a camera nobody is looking at. An iframe holds its
    // own WebSocket/peer open and an MJPEG stream is a request that never
    // completes; browsers allow only a handful per host, so leaks would
    // eventually starve new ones. Blanking the source tears both down.
    if (_transport == CameraTransport.go2rtc) {
      (_element as web.HTMLIFrameElement).src = 'about:blank';
    } else {
      (_element as web.HTMLImageElement).src = '';
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
