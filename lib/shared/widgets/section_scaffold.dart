import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/skins.dart';
import '../../design/tokens.dart';

/// One header for every Manage section — house *and* admin.
///
/// The nav rail has only two destinations (Home and Manage), so a section
/// reached from Manage has no rail entry of its own: the single way back up is
/// an in-page back arrow. That arrow used to exist only on the admin pages (the
/// old `AdminScaffold`) and was missing from the studio surfaces like Plugins,
/// which is exactly how the app grew two header patterns where only one
/// navigated. This is that one pattern: back arrow → Manage, a title, optional
/// inline stats, and optional actions, rendered in the Midnight skin the
/// app-native surfaces use regardless of the shell around them.
class SectionScaffold extends StatelessWidget {
  const SectionScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.stats = const [],
    this.actions = const [],
    this.onBack,
  });

  final String title;
  final String? subtitle;

  /// Live counts shown inline beside the title, à la the Plugins header.
  final List<SectionStat> stats;
  final List<Widget> actions;
  final Widget child;

  /// Where the back arrow goes. Defaults to Manage — these are all Manage
  /// sub-sections, so "up" is always Manage, whether you arrived by pushing
  /// from the list or by jumping straight here from the command palette.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: hcTheme(HcSkin.midnight),
      child: Builder(builder: (context) {
        final t = HcTokens.of(context);
        return ColoredBox(
          color: t.surface.base,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      t.space.sm, t.space.md, t.space.lg, t.space.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_rounded,
                            color: t.surface.onBaseMuted),
                        tooltip: 'Manage',
                        onPressed: onBack ?? () => context.go('/manage'),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: t.surface.onBase,
                                fontSize: 26,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.4,
                              ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle!,
                                style: TextStyle(
                                  color: t.surface.onBaseMuted,
                                  fontSize: 12.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (stats.isNotEmpty) ...[
                        const SizedBox(width: 18),
                        Flexible(
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 6,
                            children: [for (final s in stats) _Stat(s)],
                          ),
                        ),
                      ],
                      const Spacer(),
                      ...actions,
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: t.stroke.hairline),
              Expanded(child: child),
            ],
          ),
        );
      }),
    );
  }
}

/// The meaning of a stat's dot, resolved to a Midnight token colour inside the
/// header (which is themed) rather than at the call site (which is not — the
/// caller lives under the shell's own skin).
enum SectionTone { active, danger, warn, success, neutral }

/// A single inline count in the header: an optional coloured dot, a value, and
/// a muted label — "12 rules", "2 offline".
class SectionStat {
  const SectionStat({
    required this.value,
    required this.label,
    this.tone = SectionTone.neutral,
    this.glow = false,
  });

  final String value;
  final String label;

  /// Dot meaning; [SectionTone.neutral] draws no dot (a plain count).
  final SectionTone tone;
  final bool glow;
}

class _Stat extends StatelessWidget {
  const _Stat(this.stat);
  final SectionStat stat;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final dot = switch (stat.tone) {
      SectionTone.active => t.accent.active,
      SectionTone.danger => t.accent.danger,
      SectionTone.warn => t.accent.warn,
      SectionTone.success => t.accent.success,
      SectionTone.neutral => null,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot != null) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dot,
              shape: BoxShape.circle,
              boxShadow: stat.glow
                  ? [
                      BoxShadow(
                          color: dot.withValues(alpha: 0.7), blurRadius: 9)
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 7),
        ],
        Text(stat.value,
            style: TextStyle(
                color: t.surface.onBase,
                fontWeight: FontWeight.w600,
                fontFeatures: t.numericFontFeatures)),
        if (stat.label.isNotEmpty) ...[
          const SizedBox(width: 5),
          Text(stat.label, style: TextStyle(color: t.surface.onBaseMuted)),
        ],
      ],
    );
  }
}

/// The header's primary action — an amber-tinted filled button.
class SectionHeaderAction extends StatelessWidget {
  const SectionHeaderAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(left: t.space.sm),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: t.accent.active.withValues(alpha: 0.16),
          foregroundColor: t.accent.active,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
    );
  }
}

/// A small uppercase label that titles a block inside a section body (e.g.
/// "Runtime", "Signed in as"). Distinct from the collapsible room header
/// [SectionGroupHeader] in section_group.dart.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm, top: t.space.xs),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: t.surface.onBaseMuted,
        ),
      ),
    );
  }
}
