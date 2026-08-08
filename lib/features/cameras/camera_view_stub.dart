import 'package:flutter/widgets.dart';

/// Off the web. See `camera_still_stub.dart`.
class CameraView extends StatelessWidget {
  const CameraView({
    super.key,
    required this.url,
    required this.sourceType,
    this.refreshSecs,
    this.onError,
  });

  final String url;
  final String sourceType;
  final int? refreshSecs;
  final VoidCallback? onError;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
