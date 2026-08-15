import 'package:flutter/material.dart';

import '../../core/dashboard/svg_bindings.dart';
import 'code_card.dart';

/// Your drawing, with the house wired into it.
///
/// There is almost nothing here, and that is the design: a bound SVG **is** a
/// code element whose code we wrote. It goes through [CodeCard], so it inherits
/// the sandbox, the `default-src 'none'` policy, the nonce, the skin bridge and
/// — most importantly — the same device grant. One permission model, one
/// security review, two ways in.
///
/// The consequence worth knowing: outgrowing the binding editor is not a wall.
/// The drawing and its generated script are exactly what a code element would
/// hold, so "I need a conditional here" means switching type, not starting
/// again.
class SvgCard extends StatelessWidget {
  const SvgCard({
    super.key,
    required this.config,
    this.editing = false,
    this.entered = false,
    this.onLog,
  });

  final Map<String, dynamic> config;
  final bool editing;
  final bool entered;
  final ValueChanged<String>? onLog;

  @override
  Widget build(BuildContext context) {
    final source = (config[svgSourceKey] as String?)?.trim();
    final body = buildSvgBody(
      source == null || source.isEmpty ? svgStarter : source,
      bindingsFromConfig(config),
    );

    return CodeCard(
      // The generated body replaces whatever `html` might be lying around, so
      // a card converted from a code element cannot end up running both.
      config: {...config, 'html': body},
      editing: editing,
      entered: entered,
      onLog: onLog,
    );
  }
}
