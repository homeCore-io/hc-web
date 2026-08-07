import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/vocabulary_provider.dart';
import '../../../core/rules/vocabulary.dart';
import '../../../design/hc_icons.dart';
import '../../../design/tokens.dart';

/// Says so when this app cannot express everything the core in front of it can.
///
/// Without this, drift is *invisible to the person it hurts*. A user points the
/// app at a newer core, and some of their rules simply render as "Unsupported"
/// with no explanation, or a trigger quietly shows fewer devices than it watches.
/// They have no way to tell whether the app is broken, the rule is broken, or
/// they are.
///
/// It is a notice, not an error. Nothing is wrong with their house; this app is
/// behind, and it should say which parts and get out of the way. It is silent
/// when there is nothing to say, and silent when it could not ask — an older core
/// has no `/automations/vocabulary`, and turning "I could not check" into a red
/// banner would fire on every deployment that has not been upgraded yet.
class DriftNotice extends ConsumerStatefulWidget {
  const DriftNotice({super.key});

  @override
  ConsumerState<DriftNotice> createState() => _DriftNoticeState();
}

class _DriftNoticeState extends ConsumerState<DriftNotice> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final drift = ref.watch(vocabularyDriftProvider);

    if (drift == null || drift.isEmpty) return const SizedBox.shrink();

    // A variant this app will offer but core will reject is the SERIOUS one:
    // the user can build a rule that cannot be saved. Everything else is a
    // limitation, not a trap.
    final serious = drift.inventedVariants.isNotEmpty;
    final colour = serious ? t.accent.danger : t.accent.warn;

    return Container(
      margin: EdgeInsets.fromLTRB(t.space.md, t.space.sm, t.space.md, 0),
      padding: EdgeInsets.all(t.space.sm + 2),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: t.radius.smR,
        border: Border.all(color: colour.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: t.radius.smR,
            child: Row(
              children: [
                Icon(HcIcons.warning, size: 14, color: colour),
                SizedBox(width: t.space.sm),
                Expanded(
                  child: Text(
                    _headline(drift, serious),
                    style: t.text.bodySmallStyle
                        .copyWith(fontWeight: FontWeight.w600, color: colour),
                  ),
                ),
                Icon(
                  _open ? HcIcons.caretUp : HcIcons.caretDown,
                  size: 12,
                  color: colour,
                ),
              ],
            ),
          ),
          if (_open) ...[
            SizedBox(height: t.space.sm),
            _Section(
              title: 'This core has, and this app does not know',
              detail: 'They show as "Unsupported" and cannot be created. Your '
                  'rules still work — the editor just cannot render them.',
              groups: drift.unknownVariants,
              colour: colour,
            ),
            _Section(
              title: 'Fields this app cannot show you',
              detail:
                  'They are kept when you save — the codec preserves what it '
                  'does not understand — but you cannot see or edit them here.',
              groups: drift.unknownFields,
              colour: colour,
            ),
            _Section(
              title: 'This app offers, and this core will reject',
              detail: 'Building one of these produces a rule that cannot be '
                  'saved. This app is NEWER than the core it is talking to.',
              groups: drift.inventedVariants,
              colour: colour,
            ),
            SizedBox(height: t.space.xs),
            Text(
              'Update this app, or run tool/sync-vocabulary.sh and rebuild it.',
              style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
            ),
          ],
        ],
      ),
    );
  }

  static String _headline(VocabularyDrift d, bool serious) {
    if (serious) {
      return 'This app can build rules this homeCore will refuse to save '
          '(${d.total} differences).';
    }
    final variants = d.unknownVariantCount;
    if (variants > 0) {
      return 'This homeCore knows $variants thing${variants == 1 ? '' : 's'} '
          'the rule editor does not.';
    }
    return 'This homeCore carries ${d.total} rule '
        'field${d.total == 1 ? '' : 's'} this editor cannot show.';
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.detail,
    required this.groups,
    required this.colour,
  });

  final String title;
  final String detail;
  final Map<String, List<String>> groups;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();
    final t = HcTokens.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: t.text.captionStyle
                .copyWith(fontWeight: FontWeight.w700, color: t.surface.onBase),
          ),
          Text(
            detail,
            style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
          ),
          SizedBox(height: t.space.xs),
          for (final entry in groups.entries)
            Padding(
              padding: EdgeInsets.only(bottom: 2, left: t.space.sm),
              child: Text(
                '${entry.key}: ${entry.value.join(', ')}',
                style: t.text
                    .resolve(t.text.caption, mono: true)
                    .copyWith(color: colour),
              ),
            ),
        ],
      ),
    );
  }
}
