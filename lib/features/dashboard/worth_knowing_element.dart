import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/devices/worth_knowing.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/tokens.dart';

/// What the house wants you to know, as a short list of dots.
///
/// **A feed and a digest are different questions.** `event_feed` answers *what
/// just happened* — endless, mostly nothing, and by the time you read a line it
/// is untrue. This answers *is anything wrong*, which has an end. John, seeing
/// a feed where this belonged: *"the needs you should be items needing
/// attention like low batteries and alerts not house events that flow by
/// constantly."*
///
/// One line per thing: a coloured dot, what it is, and what about it. The good
/// news is on the list too — see `worth_knowing.dart` for why a digest that
/// goes silent when the house is fine is a digest nobody trusts.
class WorthKnowingElement extends ConsumerWidget {
  const WorthKnowingElement({super.key, required this.config});

  final Map<String, dynamic> config;

  int get _limit {
    final raw = config['limit'];
    return raw is num ? raw.toInt().clamp(1, 40) : 6;
  }

  /// Whether the reassurances are shown at all.
  ///
  /// On a small panel a person may want only what is wrong. Off by default
  /// would be the wrong default — a panel that says nothing when nothing is
  /// wrong looks broken — so this is opt-out.
  bool get _quietWhenWell => config['faults_only'] == true;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value;

    if (devices == null) {
      return Text('Reading the house…',
          style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted));
    }

    var items = worthKnowing(devices,
        room: (config['area_name'] as String? ?? '').trim());
    if (_quietWhenWell) {
      items = items.where((i) => i.level != Attention.good).toList();
    }
    if (items.isEmpty) {
      return Text(
          (config['area_name'] as String? ?? '').trim().isEmpty
              ? 'Nothing needs you.'
              : 'Nothing needs you in here.',
          style: t.text.captionStyle.copyWith(color: t.accent.success));
    }

    Color ink(Attention level) => switch (level) {
          Attention.danger => t.accent.danger,
          Attention.warn => t.accent.warn,
          Attention.good => t.accent.success,
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items.take(_limit))
          Padding(
            padding: EdgeInsets.only(bottom: t.space.sm),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: ink(item.level),
                    borderRadius: BorderRadius.circular(t.radius.pill),
                  ),
                ),
                SizedBox(width: t.space.sm),
                // The name gives way, not the state: which door is less useful
                // than whether it is open, and a truncated "open" says nothing
                // at all.
                Expanded(
                  child: Text(
                    item.what,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
                  ),
                ),
                SizedBox(width: t.space.sm),
                Text(
                  item.state,
                  style: t.text.captionStyle.copyWith(
                    color: t.surface.onBaseMuted,
                    fontFamily: t.text.monoFamily,
                    fontFeatures: t.numericFontFeatures,
                  ),
                ),
              ],
            ),
          ),
        if (items.length > _limit)
          Text(
            'and ${items.length - _limit} more',
            style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
          ),
      ],
    );
  }
}
