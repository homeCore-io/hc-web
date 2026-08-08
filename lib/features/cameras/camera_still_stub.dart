import 'package:flutter/widgets.dart';

/// Off the web there is no view registry to register an `<img>` with.
///
/// It builds and occupies its space rather than throwing, so a test can render
/// a page containing cameras and assert on everything around them. It is never
/// reached in a browser.
class CameraStill extends StatelessWidget {
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
  final int refreshSecs;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
