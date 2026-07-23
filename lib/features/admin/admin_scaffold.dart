import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/skins.dart';
import '../../design/tokens.dart';

/// Shared chrome for the administration pages.
///
/// They used to share an `AdminShell` tab bar; now each is a standalone page
/// reached from Manage, so each brings its own header — a back arrow to Manage,
/// a title, and optional actions — rendered in the Midnight skin the rest of
/// the app-native surfaces use.
class AdminScaffold extends StatelessWidget {
  const AdminScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

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
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_rounded,
                            color: t.surface.onBaseMuted),
                        tooltip: 'Manage',
                        onPressed: () => context.go('/manage'),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: t.surface.onBase,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
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

/// A small text/icon action button for the header, styled for the Midnight skin.
class AdminHeaderAction extends StatelessWidget {
  const AdminHeaderAction({
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

/// A labelled group heading inside an admin page body.
class AdminSectionHeader extends StatelessWidget {
  const AdminSectionHeader(this.label, {super.key});
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
