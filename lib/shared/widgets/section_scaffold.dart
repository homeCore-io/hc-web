import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens.dart';

/// Marks everything below it as living inside a shell that already draws the
/// page chrome.
///
/// A section reached on its own is a page: back arrow, big title, the lot. The
/// same section reached inside Administration is a *pane* — the shell owns the
/// frame, and a second back arrow pointing at Manage from inside a screen you
/// did not reach from Manage is just wrong. Rather than thread a flag through
/// nine constructors, the shell declares itself here and [SectionScaffold]
/// reads it, so a page is written once and renders correctly either way.
class SectionShellScope extends InheritedWidget {
  const SectionShellScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SectionShellScope>() != null;

  @override
  bool updateShouldNotify(SectionShellScope oldWidget) => false;
}

/// One header for every Manage section — house *and* admin.
///
/// Reached on its own it is a page: back arrow → Manage, a title, optional
/// inline stats and actions, in whatever skin the shell around it resolved.
/// It used to pin Midnight here regardless of the shell, which meant a chosen
/// skin stopped at the chrome and never reached the page. That arrow used to
/// exist only on the
/// admin pages (the old `AdminScaffold`) and was missing from studio surfaces
/// like Plugins, which is how the app grew two header patterns where only one
/// navigated.
///
/// Reached inside [SectionShellScope] the same declarations render as a pane —
/// see [_pane]. One call site, both shapes.
class SectionScaffold extends StatelessWidget {
  const SectionScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.stats = const [],
    this.actions = const [],
    this.onBack,
    this.breadcrumbs = const [],
  });

  final String title;
  final String? subtitle;

  /// Trail above the title — `Manage › Administration`. The last entry is the
  /// current place and is not repeated here; [title] is it.
  final List<String> breadcrumbs;

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
    if (SectionShellScope.of(context)) return _pane(context);
    return Builder(builder: (context) {
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
                          if (breadcrumbs.isNotEmpty)
                            Text(
                              '${breadcrumbs.join('  ›  ')}  ›',
                              style: t.text.captionStyle
                                  .copyWith(color: t.surface.onBaseMuted),
                            ),
                          // One line, ellipsized. Squeezed between a back
                          // arrow and the stats on a narrow window, the
                          // default wrapping broke words down the middle —
                          // "Administratio / n" — which reads as a rendering
                          // fault rather than a long title.
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.text.displayStyle.copyWith(
                                color: t.surface.onBase,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.4),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.text.bodySmallStyle
                                  .copyWith(color: t.surface.onBaseMuted),
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
    });
  }

  /// The same section, drawn as a pane: no back arrow and no page-sized title,
  /// because the shell above already shows both. Everything the page declared
  /// about itself — its name, what it is for, its counts, its actions — is
  /// still here, one step down in the hierarchy where it belongs.
  Widget _pane(BuildContext context) {
    final t = HcTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              t.space.lg, t.space.lg, t.space.lg, t.space.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.text.titleStyle.copyWith(
                          color: t.surface.onBase, fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.text.bodySmallStyle
                            .copyWith(color: t.surface.onBaseMuted),
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
        Expanded(child: child),
      ],
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
        style: t.text.captionStyle.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: t.surface.onBaseMuted),
      ),
    );
  }
}
