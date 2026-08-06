import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/skin_provider.dart';
import '../../design/components/hc_surface.dart';
import '../../design/skins.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';

/// Choosing a skin.
///
/// The skins were always here and always complete — what was missing was any
/// way to pick one. Until now the only writer of [skinOverrideProvider] was a
/// test, so Control Room and Soft Home shipped in every build and nobody could
/// reach them.
///
/// Each option is previewed in its own skin rather than described in the
/// current one. A swatch drawn in Midnight tells you nothing about Soft Home,
/// and a list of adjectives tells you less.
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final chosen = ref.watch(skinOverrideProvider);

    return SectionScaffold(
      title: 'Appearance',
      subtitle: 'How the house looks',
      child: ListView(
        padding:
            EdgeInsets.fromLTRB(t.space.lg, t.space.sm, t.space.lg, t.space.xl),
        children: [
          _Option(
            selected: chosen == null,
            label: 'Follow the surface',
            description:
                'Ambient Glass on a wall panel, Midnight everywhere else. '
                'A panel across a dark room and a phone in your hand are not '
                'the same screen, and this lets them differ.',
            preview: const _FollowPreview(),
            onTap: () => ref.read(skinOverrideProvider.notifier).choose(null),
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: t.space.md),
            child: Divider(height: 1, color: t.stroke.hairline),
          ),
          for (final skin in HcSkin.values)
            Padding(
              padding: EdgeInsets.only(bottom: t.space.sm),
              child: _Option(
                selected: chosen == skin,
                label: skin.label,
                description: skin.description,
                preview: _SkinPreview(skin: skin),
                onTap: () =>
                    ref.read(skinOverrideProvider.notifier).choose(skin),
              ),
            ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.selected,
    required this.label,
    required this.description,
    required this.preview,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final String description;
  final Widget preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Semantics(
      selected: selected,
      button: true,
      label: label,
      // HcSurface rather than a hand-rolled card with an InkWell: it carries
      // the press physics, the selection border and the glass handling that
      // every other tappable card in the app already has — and it does not
      // need a Material ancestor, which a SectionScaffold does not provide.
      child: HcSurface(
        selected: selected,
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            preview,
            SizedBox(width: t.space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: t.text.subtitleStyle.copyWith(
                        color: t.surface.onBase, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: t.space.xs),
                  Text(
                    description,
                    style: t.text.bodyStyle
                        .copyWith(color: t.surface.onBaseMuted, height: 1.4),
                  ),
                ],
              ),
            ),
            SizedBox(width: t.space.sm),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? t.accent.primary : t.surface.onBaseMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// A skin, drawn in itself: its page colour, a card on it, and the accent an
/// active device would emit. Small, but it is the real palette rather than a
/// description of one.
///
/// The glass matters here. Midnight is deliberately "Ambient Glass with the
/// glass taken out", so on colour alone their previews are the same picture and
/// the one thing that separates them is invisible. A glass skin therefore gets
/// a real BackdropFilter over a ground with something in it to blur — at a
/// scaled-down sigma, since 24 across 84 pixels is a smear rather than a
/// frost.
class _SkinPreview extends StatelessWidget {
  const _SkinPreview({required this.skin, this.width = 84, this.height = 58});

  final HcSkin skin;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = skin.tokens;

    final cardRadius = BorderRadius.circular(5);

    Widget card = Container(
      decoration: BoxDecoration(
        // A glass skin tints the blurred backdrop; a flat one is opaque.
        color: s.surface.isGlass ? s.surface.glassTint : s.surface.raised,
        borderRadius: cardRadius,
        border: Border.all(color: s.stroke.hairline),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: s.accent.active,
              shape: BoxShape.circle,
              // The signature effect, at 8 pixels: an active device
              // emits light onto its own card.
              boxShadow: [
                BoxShadow(
                  color: s.accent.active
                      .withValues(alpha: s.glow.strength.clamp(0, 1)),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 3,
              color: s.surface.onBaseMuted.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );

    if (s.surface.isGlass) {
      card = ClipRRect(
        borderRadius: cardRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: s.surface.glassBlur * 0.3,
            sigmaY: s.surface.glassBlur * 0.3,
          ),
          child: card,
        ),
      );
    }

    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: s.surface.base,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: s.stroke.hairline),
        // Something for the blur to find. A frost over a flat fill is
        // indistinguishable from a flat fill.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            s.surface.base,
            Color.alphaBlend(
                s.accent.active.withValues(alpha: 0.22), s.surface.base),
            s.surface.base,
          ],
        ),
      ),
      padding: const EdgeInsets.all(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: card),
          const SizedBox(height: 5),
          Row(
            children: [
              Container(width: 18, height: 4, color: s.accent.primary),
              const SizedBox(width: 4),
              Expanded(
                  child: Container(
                      height: 4,
                      color: s.surface.onBaseMuted.withValues(alpha: 0.3))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Both defaults side by side, because "follow the surface" is a choice about
/// two screens rather than a refusal to choose.
class _FollowPreview extends StatelessWidget {
  const _FollowPreview();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 84,
        height: 58,
        child: Row(
          children: [
            Expanded(
              child: _SkinPreview(
                skin: HcSkin.defaultFor(HcShell.wall),
                width: 40,
                height: 58,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _SkinPreview(
                skin: HcSkin.defaultFor(HcShell.touch),
                width: 40,
                height: 58,
              ),
            ),
          ],
        ),
      );
}
