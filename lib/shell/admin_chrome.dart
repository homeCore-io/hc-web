import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/auth_provider.dart';
import '../design/tokens.dart';
import 'command_palette.dart';
import 'session_status.dart';
import 'shell_scope.dart';

/// The operator's desk.
///
/// Dense, hairlined, keyboard-first. Every pixel spent on chrome is a pixel not
/// spent on a row of data, so the rail is icons-only and the header is one line
/// tall. The way you actually move around here is Cmd-K.
class AdminChrome extends ConsumerWidget {
  const AdminChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final location = GoRouterState.of(context).matchedLocation;

    return CommandPaletteScope(
      child: Scaffold(
        body: Column(
          children: [
            const ExpiryBanner(),
            _header(context, ref, t),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  _rail(context, t, location),
                  const VerticalDivider(width: 1),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, WidgetRef ref, HcTokens t) => SizedBox(
        height: 44,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space.md),
          child: Row(
            children: [
              Icon(Icons.hub_outlined, size: 16, color: t.accent.primary),
              SizedBox(width: t.space.sm),
              Text(
                'HomeCore',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: t.surface.onBase,
                ),
              ),
              SizedBox(width: t.space.md),

              // The palette is advertised rather than hidden: an operator who
              // does not know the shortcut exists will never guess it.
              _PaletteButton(),

              const Spacer(),
              const LiveDot(showLabel: true),
              SizedBox(width: t.space.md),
              IconButton(
                iconSize: 16,
                icon: const Icon(Icons.logout),
                tooltip: 'Sign out',
                onPressed: () => ref.read(authProvider.notifier).logout(),
              ),
            ],
          ),
        ),
      );

  Widget _rail(BuildContext context, HcTokens t, String location) => Container(
        width: 52,
        color: t.surface.raised,
        child: Column(
          children: [
            SizedBox(height: t.space.sm),
            for (final item in kNavItems)
              _RailButton(
                item: item,
                selected: location.startsWith(item.route),
              ),
          ],
        ),
      );
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.item, required this.selected});

  final NavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Tooltip(
      message: item.label,
      child: InkWell(
        onTap: () => context.go(item.route),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            // A hairline bar, not a filled pill: depth in this skin comes from
            // strokes, and a pill would eat the density we came for.
            border: Border(
              left: BorderSide(
                color: selected ? t.accent.primary : Colors.transparent,
                width: 2,
              ),
            ),
            color: selected
                ? t.accent.primary.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          child: Icon(
            item.icon,
            size: 18,
            color: selected ? t.accent.primary : t.surface.onBaseMuted,
          ),
        ),
      ),
    );
  }
}

class _PaletteButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);

    return InkWell(
      onTap: () => showCommandPalette(context, ref),
      borderRadius: t.radius.smR,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: t.space.sm,
          vertical: t.space.xs,
        ),
        decoration: BoxDecoration(
          color: t.surface.sunken,
          borderRadius: t.radius.smR,
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 13, color: t.surface.onBaseMuted),
            SizedBox(width: t.space.xs),
            Text(
              'Jump to…',
              style: TextStyle(fontSize: 12, color: t.surface.onBaseMuted),
            ),
            SizedBox(width: t.space.md),
            Text(
              '⌘K',
              style: TextStyle(
                fontSize: 11,
                fontFeatures: t.numericFontFeatures,
                color: t.surface.onBaseMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
