import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/vocabulary.dart';
import '../../core/providers/dashboard_vocabulary_provider.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';

/// Says so when this app cannot draw everything the core in front of it can
/// store.
///
/// The dashboard sibling of `automations/widgets/drift_notice.dart`, and it
/// exists for the same reason: drift is otherwise *invisible to the person it
/// hurts*. A card renders as an empty rectangle, or a save is refused, and
/// there is no way to tell whether the app is behind, the card is broken, or
/// they are.
///
/// It is a notice, not an error. Nothing is wrong with their house; this app is
/// behind, and it should say which parts and get out of the way. Silent when
/// there is nothing to say, and silent when it could not ask — an older core
/// has no `/dashboards/vocabulary`, and turning "I could not check" into a
/// banner would fire on every deployment that has not been upgraded yet.
class DashboardDriftNotice extends ConsumerStatefulWidget {
  const DashboardDriftNotice({super.key});

  @override
  ConsumerState<DashboardDriftNotice> createState() =>
      _DashboardDriftNoticeState();
}

class _DashboardDriftNoticeState extends ConsumerState<DashboardDriftNotice> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final drift = ref.watch(dashboardDriftProvider);

    if (drift == null || drift.isEmpty) return const SizedBox.shrink();

    // A required field the editor cannot set is the SERIOUS one: the card saves
    // nowhere, and core rejects the whole dashboard on the first bad widget —
    // so it costs every other edit made in the same sitting. Everything else
    // here is a limitation, not a trap.
    final serious = drift.unfillableFields.isNotEmpty;
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
              title: 'Cards this homeCore has, and this app does not know',
              detail: 'They render as an unknown card. The dashboards still '
                  'work — this editor just cannot draw them.',
              items: drift.unknownWidgets,
              colour: colour,
            ),
            _Section(
              title: 'Settings this app cannot let you fill in',
              detail: 'This core requires them, and this editor offers no way '
                  'to set one — so a card built here would be refused, and a '
                  'refused card costs the whole dashboard on save.',
              items: drift.unfillableFields,
              colour: colour,
            ),
            _Section(
              title: 'Instruments a plugin card may ask for',
              detail: 'A plugin can build a card out of these, and this app '
                  'cannot draw them yet. Such a card says so where it sits.',
              items: drift.undrawableElements,
              colour: colour,
            ),
            SizedBox(height: t.space.xs),
            Text(
              'Update this app, or run tool/sync-dashboard-vocabulary.sh and '
              'rebuild it.',
              style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
            ),
          ],
        ],
      ),
    );
  }

  static String _headline(DashboardDrift d, bool serious) {
    if (serious) {
      final n = d.unfillableFields.length;
      return 'This app can build cards this homeCore will refuse to save '
          '($n setting${n == 1 ? '' : 's'} it cannot fill in).';
    }
    if (d.unknownWidgets.isNotEmpty) {
      final n = d.unknownWidgets.length;
      return 'This homeCore knows $n card${n == 1 ? '' : 's'} this app cannot '
          'draw.';
    }
    final n = d.undrawableElements.length;
    return 'A plugin card here may use $n '
        'instrument${n == 1 ? '' : 's'} this app cannot draw.';
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.detail,
    required this.items,
    required this.colour,
  });

  final String title;
  final String detail;
  final List<String> items;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
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
          Padding(
            padding: EdgeInsets.only(bottom: 2, left: t.space.sm),
            child: Text(
              items.join(', '),
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
