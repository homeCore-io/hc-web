import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/card_style.dart';
import '../../core/devices/breakdown.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/tokens.dart';

/// What the house is made of, as a row of lit bars.
///
/// The mockup's version of this panel is eight labelled bars whose lengths are
/// compared to each other, and John: *"the 'house made of' in the mockup has a
/// nice lighted bar like a progress bar."* Counters tell you eight numbers and
/// leave the comparing to you; the bars do the comparing, which is the whole
/// reason the panel exists.
///
/// The counting and ordering live in `breakdown.dart`; this only draws.
class BreakdownElement extends ConsumerWidget {
  const BreakdownElement({super.key, required this.config});

  final Map<String, dynamic> config;

  Breakdown get _by => Breakdown.named(config['group_by']);

  int get _limit {
    final raw = config['limit'];
    return raw is num ? raw.toInt().clamp(1, 40) : 8;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value;

    if (devices == null) {
      return Text('Counting…',
          style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted));
    }

    final slices = breakdownOf(devices, _by, limit: _limit);
    if (slices.isEmpty) {
      return Text('Nothing to count yet.',
          style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted));
    }

    final ink = resolveInk(t, config['ink'] as String?) ?? t.accent.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final slice in slices)
          Padding(
            padding: EdgeInsets.only(bottom: t.space.sm),
            child: Row(
              children: [
                // A fixed label column so every bar starts at the same x —
                // bars that each begin somewhere different cannot be compared
                // by eye, which is the one thing they are for.
                SizedBox(
                  width: 92,
                  child: Text(
                    slice.what,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted),
                  ),
                ),
                SizedBox(width: t.space.sm),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(t.radius.pill),
                    child: Stack(
                      children: [
                        Container(height: 6, color: t.stroke.hairline),
                        FractionallySizedBox(
                          widthFactor: slice.fraction.clamp(0.0, 1.0),
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(t.radius.pill),
                              // Lit rather than flat: the bar fades in from the
                              // left the way the mockup's does, so a long bar
                              // reads as a quantity and not as a block of ink.
                              gradient: LinearGradient(
                                colors: [ink.withValues(alpha: 0.45), ink],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: t.space.sm),
                SizedBox(
                  width: 30,
                  child: Text(
                    '${slice.count}',
                    textAlign: TextAlign.end,
                    style: t.text.captionStyle.copyWith(
                      color: t.surface.onBase,
                      fontFamily: t.text.monoFamily,
                      fontFeatures: t.numericFontFeatures,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
