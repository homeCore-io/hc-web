import 'package:flutter/material.dart';

import '../../core/dashboard/design_tools.dart';
import '../../design/tokens.dart';

/// The tool strip: what you are holding.
///
/// **A design application has tools; a content editor has a catalogue.** That
/// difference is not cosmetic — it decides the order you work in. With a
/// catalogue you choose a thing and then decide where it goes; with a tool you
/// decide the shape of the space first and the element fills it. Laying out a
/// page is the second kind of work, which is why this strip is permanent
/// furniture and the catalogue is now one tool among several.
///
/// Vertical and narrow, at the edge of the canvas, the way every drawing
/// application since MacPaint has put it. The position is doing work: the tools
/// sit against the surface they act on, so the distance between choosing a tool
/// and using it is a few pixels rather than a trip to the far side of the
/// window.
class ToolPalette extends StatelessWidget {
  const ToolPalette({
    super.key,
    required this.tool,
    required this.onTool,
  });

  final DesignTool tool;
  final ValueChanged<DesignTool> onTool;

  /// The strip's width. Fixed, and one tool wide: a tool strip that reflowed
  /// would move the tool you were about to click.
  static const double width = 44;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: t.surface.base,
        border: Border(
          right: BorderSide(color: t.stroke.hairline, width: t.stroke.width),
        ),
      ),
      child: Column(
        children: [
          SizedBox(height: t.space.xs),
          for (final each in DesignTool.values) ...[
            // Select is the tool you return to, so it is set apart from the
            // ones that make things rather than sitting first in a list of
            // equals.
            if (each == DesignTool.text)
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: t.space.sm, vertical: t.space.xs),
                child:
                    Divider(height: t.stroke.width, color: t.stroke.hairline),
              ),
            _ToolButton(
              tool: each,
              on: each == tool,
              onTap: () => onTool(each),
            ),
          ],
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton(
      {required this.tool, required this.on, required this.onTap});

  final DesignTool tool;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space.xs, vertical: 1),
      child: Tooltip(
        // The key is on the tooltip, not hidden in a help page: a tool strip
        // whose shortcuts you have to go and read is one nobody is fast in.
        message: '${tool.label}  ${tool.shortcut}',
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(t.radius.sm),
          child: Container(
            height: t.density.minTapTarget,
            decoration: BoxDecoration(
              color: on ? t.accent.active.withValues(alpha: 0.16) : null,
              borderRadius: BorderRadius.circular(t.radius.sm),
            ),
            child: Icon(
              toolIcon(tool.icon),
              size: 18,
              color: on ? t.accent.active : t.surface.onBaseMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// A tool's icon name as an icon.
///
/// The names live in [DesignTool] as strings so the tool set stays plain data —
/// a test can read what the toolbar offers without building a widget, and the
/// list is not quietly coupled to an icon font.
IconData toolIcon(String name) => switch (name) {
      'cursor' => Icons.near_me_outlined,
      'text' => Icons.text_fields_outlined,
      'shape' => Icons.pentagon_outlined,
      'line' => Icons.show_chart_outlined,
      'image' => Icons.image_outlined,
      'gauge' => Icons.speed_outlined,
      'code' => Icons.code_outlined,
      'card' => Icons.dashboard_customize_outlined,
      _ => Icons.help_outline,
    };
