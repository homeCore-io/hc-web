/// The two controls both inspector panes need.
///
/// They were private to `page_inspector.dart`, which was fine while it was the
/// only pane with settings on it. The designer's group section needs the same
/// two, and a second copy of a labelled toggle is how two panes end up with the
/// same control at subtly different heights — so they live here instead, with
/// no more surface than the two of them.
library;

import 'package:flutter/material.dart';

import '../../design/components/hc_controls.dart';
import '../../design/tokens.dart';

/// A setting that is on or off, named on the left.
class InspectorToggle extends StatelessWidget {
  const InspectorToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs / 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: t.text.bodyStyle.copyWith(
                    color: onChanged == null
                        ? t.surface.onBaseMuted
                        : t.surface.onBase)),
          ),
          HcToggle(
            value: value,
            onChanged: onChanged,
            semanticLabel: label,
          ),
        ],
      ),
    );
  }
}

/// A number you set by dragging, with the value shown so it can be read back.
class InspectorSlider extends StatelessWidget {
  const InspectorSlider({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Row(
      children: [
        // Wide enough for the longest label any pane uses. At 44 it fitted
        // 'Blur' and 'Dim' and broke 'Padding' across two lines, mid-word.
        SizedBox(
          width: 60,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            max: max,
            divisions: max.round(),
            label: '${value.round()}',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 28,
          child: Text('${value.round()}',
              textAlign: TextAlign.right,
              style: t.text.captionStyle.copyWith(
                  color: t.surface.onBaseMuted,
                  fontFeatures: t.numericFontFeatures)),
        ),
      ],
    );
  }
}
