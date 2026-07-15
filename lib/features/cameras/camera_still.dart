import 'dart:async';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'camera_source.dart';

/// A camera shown as a refreshing still, not a live stream.
///
/// This is what the cameras that are NOT the active one look like: a snapshot
/// re-fetched on a timer. It is cheap — one small JPEG every few seconds instead
/// of a decoded video stream — which is the entire reason an 8-inch tablet can
/// show a wall of cameras at all.
///
/// The tap handler is attached to the `<img>` ELEMENT, not to a Flutter widget
/// over it. That is deliberate: a platform view (this image) captures every
/// pointer event in its rectangle, so a Flutter `GestureDetector` wrapped around
/// it would never fire — the same reason a delete button floated over a live
/// iframe is dead. Handling the click inside the HTML element sidesteps that
/// entirely.
class CameraStill extends StatefulWidget {
  const CameraStill({
    super.key,
    required this.url,
    required this.sourceType,
    required this.onTap,
    this.refreshSecs = 8,
  });

  final String url;
  final String sourceType;
  final VoidCallback onTap;

  /// A still does not need to be fresh to the second — it is a thumbnail you
  /// glance at, not the feed you are watching. Slower refresh, less load.
  final int refreshSecs;

  @override
  State<CameraStill> createState() => _CameraStillState();
}

class _CameraStillState extends State<CameraStill> {
  late final String _viewType;
  late final web.HTMLImageElement _img;
  Timer? _tick;
  int _frame = 0;

  static int _seq = 0;

  @override
  void initState() {
    super.initState();
    _viewType = 'hc-still-${_seq++}';
    _img = web.HTMLImageElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.display = 'block'
      ..style.cursor = 'pointer';
    _img.onClick.listen((_) => widget.onTap());

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _img);

    _load();
  }

  String get _stillUrl => stillUrlFor(widget.url, widget.sourceType);

  void _load() {
    _tick?.cancel();
    _img.src = cameraSrc(_stillUrl, 'image_refresh', _frame);
    final secs = widget.refreshSecs.clamp(2, 300);
    _tick = Timer.periodic(Duration(seconds: secs), (_) {
      _frame++;
      _img.src = cameraSrc(_stillUrl, 'image_refresh', _frame);
    });
  }

  @override
  void didUpdateWidget(covariant CameraStill old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.sourceType != widget.sourceType) {
      _load();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _img.src = '';
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
