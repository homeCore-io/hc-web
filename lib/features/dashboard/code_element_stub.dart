import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// The code element where there is no browser to run it in.
///
/// A platform view is a real DOM element, so this card exists only on web. The
/// stub says so rather than rendering an empty box, because a card that draws
/// nothing on one platform and a gauge on another is a bug report waiting to be
/// filed against the wrong thing.
class CodeElement extends StatelessWidget {
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

  final String html;
  final Map<String, String> cssVars;
  final String states;
  final String nonce;
  final bool live;
  final bool allowNetwork;
  final String? assetOrigin;
  final void Function(String id, Map<String, dynamic> patch)? onSet;
  final ValueChanged<String>? onLog;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(t.space.md),
        child: Text(
          'A code element runs in a browser. This build has no place to run it.',
          textAlign: TextAlign.center,
          style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
        ),
      ),
    );
  }
}
