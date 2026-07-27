import 'package:flutter/material.dart';

import '../design/hc_icons.dart';
import '../design/tokens.dart';

/// Detail, laid OVER the thing it is about.
///
/// This is the difference between an app and a website, and it is worth being
/// precise about why. Tapping a device used to `push('/devices/:id')` — a route.
/// The house vanished, a new page arrived with its own AppBar and its own title,
/// and getting back meant a Back button. You lost your place, every time, for
/// something as small as checking a lamp's brightness.
///
/// A sheet slides over the house and leaves it visible behind. You never leave;
/// you look, you act, you dismiss. The house is still lit exactly where it was.
///
/// It arrives from the RIGHT on a wide screen and from the BOTTOM on a narrow
/// one — not for novelty, but because a phone's reachable area is the bottom of
/// the screen and a desktop's spare space is the side. Same sheet, same content.
Future<T?> showHcSheet<T>(
  BuildContext context, {
  required Widget child,
  String? title,
}) {
  final wide = MediaQuery.sizeOf(context).width >= 720;
  final t = HcTokens.of(context);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title ?? 'Details',
    // Dimmed, not opaque: the house stays legible behind, which is the whole
    // point of not having navigated away from it.
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: t.motion.base,
    pageBuilder: (context, _, __) => _SheetFrame(wide: wide, child: child),
    transitionBuilder: (context, anim, _, sheet) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: wide ? const Offset(1, 0) : const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: sheet,
      );
    },
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.wide, required this.child});

  final bool wide;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    final panel = Container(
      decoration: BoxDecoration(
        color: t.surface.overlay,
        borderRadius: wide
            ? BorderRadius.horizontal(left: t.radius.lgR.topLeft)
            : BorderRadius.vertical(top: t.radius.lgR.topLeft),
        border: Border(
          left: wide ? BorderSide(color: t.stroke.hairline) : BorderSide.none,
          top: wide ? BorderSide.none : BorderSide(color: t.stroke.hairline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!wide) const _Grabber(),
            Flexible(child: child),
          ],
        ),
      ),
    );

    return Align(
      alignment: wide ? Alignment.centerRight : Alignment.bottomCenter,
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // Scales with the window instead of a flat 460.
            //
            // 460 was set when the panel was a header and a list of rows. It is
            // too narrow for what it holds now — a media card, a D-pad, a
            // wrapped strip of verbs — and it wasted the room a desktop has
            // anyway. Floor 520 so the blocks are never cramped, ceiling 760 so
            // it stays a drawer laid over the house rather than a second page.
            maxWidth: wide
                ? (MediaQuery.sizeOf(context).width * 0.44).clamp(520.0, 760.0)
                : double.infinity,
            maxHeight: MediaQuery.sizeOf(context).height * (wide ? 1.0 : 0.88),
            minHeight: wide ? MediaQuery.sizeOf(context).height : 0,
          ),
          child: panel,
        ),
      ),
    );
  }
}

/// The drag handle a bottom sheet needs to look draggable.
class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.sm),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: t.surface.onBaseMuted.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// A sheet's header: what this is, and the way out.
class HcSheetHeader extends StatelessWidget {
  const HcSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Padding(
      padding:
          EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.sm, t.space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: t.surface.onBase,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: t.surface.onBaseMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
          IconButton(
            icon: const Icon(HcIcons.x, size: 16),
            tooltip: 'Close',
            color: t.surface.onBaseMuted,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
