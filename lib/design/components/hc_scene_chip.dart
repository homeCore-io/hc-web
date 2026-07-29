import 'package:flutter/material.dart';

import '../tokens.dart';
import 'hc_surface.dart';

/// A scene, as the light it makes.
///
/// Lifted out of the Scenes page so the device panel can show the same chip: a
/// Hue scene belongs to a room, so the lights in that room are exactly where
/// you would reach for it, and two different-looking scene chips in one product
/// would be the tell that they were built by different hands.

// ── Scene palette ──────────────────────────────────────────────────────────────

/// The colours a scene paints the room in, keyed off its name where the bridge
/// doesn't hand us the real palette. Drives the chip's dot, hover glow, and —
/// for the active scene — the drifting aurora border.
class ScenePalette {
  const ScenePalette(this.dot, this.gradient);
  final Color dot;
  final List<Color> gradient;
}

const kScenePalettes = <String, ScenePalette>{
  'relax': ScenePalette(Color(0xFFFFB661),
      [Color(0xFFFFB661), Color(0xFFFF8A5B), Color(0xFFE24C4C)]),
  'read': ScenePalette(Color(0xFFFFC97A),
      [Color(0xFFFFE3B0), Color(0xFFFFC97A), Color(0xFFFF9A5B)]),
  'concentrate': ScenePalette(Color(0xFFBCD8FF),
      [Color(0xFFEAF2FF), Color(0xFF9DC4FF), Color(0xFF7CC4FF)]),
  'energize': ScenePalette(Color(0xFF5BE0C0),
      [Color(0xFFDFF6FF), Color(0xFF7CC4FF), Color(0xFF4CE0D0)]),
  'nightlight': ScenePalette(Color(0xFFC25A3A),
      [Color(0xFFC25A3A), Color(0xFF7A3B2A), Color(0xFF3A2018)]),
  'bright': ScenePalette(Color(0xFFFFFFFF),
      [Color(0xFFFFFFFF), Color(0xFFE9EDF2), Color(0xFFBFC7D2)]),
  'dimmed':
      ScenePalette(Color(0xFFB79A6A), [Color(0xFF6B5B45), Color(0xFF4A3F30)]),
  'savanna': ScenePalette(Color(0xFFFF6B4A),
      [Color(0xFFFF9A5B), Color(0xFFE24C4C), Color(0xFFB03050)]),
  'aurora': ScenePalette(Color(0xFF5BE0C0),
      [Color(0xFF5BE0C0), Color(0xFF4C9EE2), Color(0xFF7C6BFF)]),
  'blossom': ScenePalette(Color(0xFFFF9EC4),
      [Color(0xFFFF9EC4), Color(0xFFE24C9E), Color(0xFFB03050)]),
  'twilight': ScenePalette(Color(0xFFB98BFF),
      [Color(0xFFB98BFF), Color(0xFFFF8ABF), Color(0xFFFF8A5B)]),
  'mountain': ScenePalette(Color(0xFFBCDCFF),
      [Color(0xFFBCDCFF), Color(0xFF7C9EE2), Color(0xFF5B6BE0)]),
  'on air':
      ScenePalette(Color(0xFFFF5B5B), [Color(0xFFFF5B5B), Color(0xFFB03030)]),
};

ScenePalette? scenePaletteFor(String name) {
  final n = name.toLowerCase();
  for (final e in kScenePalettes.entries) {
    if (n.contains(e.key)) return e.value;
  }
  return null;
}

// ── Scene chip (B: colour glow · D: aurora edge when active) ─────────────────────

class HcSceneChip extends StatefulWidget {
  const HcSceneChip({
    super.key,
    required this.name,
    required this.onRun,
    this.active = false,
    this.onEdit,
  });

  final String name;
  final VoidCallback onRun;

  /// The scene currently showing in the room. At most one, so at most one
  /// aurora ring animates.
  final bool active;

  /// Non-null for a scene homeCore owns and can edit. A bridge's own scene is
  /// run-only, and drawing a pencil that opens nothing is worse than no pencil.
  final VoidCallback? onEdit;

  @override
  State<HcSceneChip> createState() => _HcSceneChipState();
}

class _HcSceneChipState extends State<HcSceneChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final p = scenePaletteFor(widget.name);
    final custom = widget.onEdit != null;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final content = _content(t, p, custom);

    // Active scene with a known palette gets the animated aurora ring (D).
    if (widget.active && p != null && !reduce) {
      return _AuroraChip(palette: p, onTap: widget.onRun, child: content);
    }

    // Everything else is a colour-glow pill (B): raised HcSurface, a palette
    // dot, and a soft glow in the scene's colour on hover (persistent if the
    // scene is active but has no palette to animate).
    final glowColor = p?.dot ?? (widget.active ? t.accent.active : null);
    final intensity = widget.active ? 0.6 : (_hover && p != null ? 0.5 : 0.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: HcSurface(
        onTap: widget.onRun,
        glowColor: glowColor,
        glowIntensity: intensity,
        padding: EdgeInsets.fromLTRB(11, 8, custom ? 7 : 13, 8),
        child: content,
      ),
    );
  }

  Widget _content(HcTokens t, ScenePalette? p, bool custom) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (p != null)
          _Dot(color: p.dot)
        else
          Icon(Icons.play_arrow_rounded,
              size: 14, color: t.surface.onBaseMuted),
        const SizedBox(width: 9),
        Text(widget.name,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: widget.active ? t.accent.active : t.surface.onBase)),
        if (custom) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: widget.onEdit,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.edit_outlined,
                  size: 13, color: t.surface.onBaseMuted),
            ),
          ),
        ],
      ],
    );
  }
}

/// The scene's colour as a small glowing dot.
class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
        ],
      ),
    );
  }
}

/// The active scene: a slowly-drifting gradient border in the scene's palette,
/// with a matching bloom. Reserved for the one active scene, so at most a
/// handful animate at once.
class _AuroraChip extends StatefulWidget {
  const _AuroraChip(
      {required this.palette, required this.onTap, required this.child});
  final ScenePalette palette;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_AuroraChip> createState() => _AuroraChipState();
}

class _AuroraChipState extends State<_AuroraChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final colors = [...widget.palette.gradient, widget.palette.gradient.first];

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => Container(
          decoration: BoxDecoration(
            gradient: SweepGradient(
              colors: colors,
              transform: GradientRotation(_c.value * 6.2831853),
            ),
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: widget.palette.dot.withValues(alpha: 0.45),
                blurRadius: 18,
                spreadRadius: -4,
              ),
            ],
          ),
          padding: const EdgeInsets.all(1.6),
          child: child,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: t.surface.raised,
            borderRadius: BorderRadius.circular(9.6),
          ),
          padding: const EdgeInsets.fromLTRB(11, 8, 13, 8),
          child: widget.child,
        ),
      ),
    );
  }
}
