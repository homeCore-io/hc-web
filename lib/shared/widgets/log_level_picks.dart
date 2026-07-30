import 'package:flutter/material.dart';

import '../../core/models/log_level_directive.dart';
import '../../design/tokens.dart';

/// The five levels, as chips.
///
/// Shared by core's log-level dialog and each plugin's, because they are the
/// same control over the same vocabulary — core and every Rust plugin filter
/// through the same `hc_logging` handle, so a directive means the same thing on
/// both sides.
class LogLevelPicks extends StatelessWidget {
  const LogLevelPicks({
    super.key,
    required this.selected,
    required this.onPick,
    this.enabled = true,
  });

  /// The level currently in force, when it is one of the five.
  final String? selected;
  final ValueChanged<String> onPick;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final level in logLevels)
          InkWell(
            onTap: enabled ? () => onPick(level) : null,
            borderRadius: BorderRadius.circular(t.radius.pill),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected == level
                    ? t.accent.active.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(t.radius.pill),
                border: Border.all(
                  color:
                      selected == level ? t.accent.active : t.stroke.hairline,
                ),
              ),
              child: Text(
                level,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: !enabled
                      ? t.surface.onBaseMuted
                      : selected == level
                          ? t.accent.active
                          : t.surface.onBaseMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
