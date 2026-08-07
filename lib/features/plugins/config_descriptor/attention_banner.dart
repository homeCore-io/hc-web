import 'package:flutter/material.dart';

import '../../../design/tokens.dart';
import 'descriptor.dart';

/// "2 devices need a Kind" — said above the table, not inside it.
///
/// A column marked `prompt_when_empty` is *wanted* but not *required*: the row
/// saves without it, and the plugin decides what an unfilled row means. Caséta
/// is the case that showed why that needs announcing. A Lutron integration
/// report carries no load type, so every imported zone arrives with no Kind;
/// the plugin skips such a device at startup and logs a warning rather than
/// refusing to parse — which once took the whole plugin offline. Nine rows go
/// into the config and two devices come out.
///
/// The renderer already marked the individual rows. That does not help when the
/// complaint is that the devices are *not where you expected them* and you are
/// therefore not looking at the rows at all.
///
/// Lives in its own file because `descriptor_renderer.dart` imports
/// `package:web` and so cannot be widget-tested off the browser. Nothing here
/// knows what Caséta is: the count, the column name and the noun all come from
/// the descriptor, so any plugin marking a column gets this.
class AttentionBanner extends StatelessWidget {
  const AttentionBanner({
    super.key,
    required this.field,
    required this.count,
  });

  /// The table field, for its label and its prompted column.
  final CfgField field;

  /// How many rows are missing the prompted column's value.
  final int count;

  /// Rows still wanting a `prompt_when_empty` column.
  ///
  /// Empty string counts as missing, not as a choice: a config round-trip can
  /// turn an absent value into `""`, and a check for null alone would go quiet
  /// while the plugin still skipped the row.
  static int countNeedingAttention(
      CfgField field, List<Map<String, dynamic>> rows) {
    return rows.where((r) => rowNeedsAttention(field, r)).length;
  }

  static bool rowNeedsAttention(CfgField field, Map<String, dynamic> row) {
    for (final c in field.itemFields ?? const <CfgField>[]) {
      if (!c.promptWhenEmpty || c.key == null) continue;
      final v = row[c.key];
      if (v == null || (v is String && v.isEmpty)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final col = (field.itemFields ?? const <CfgField>[])
        .where((c) => c.promptWhenEmpty)
        .firstOrNull;
    final what = col?.label ?? 'a value';
    final one = count == 1;
    final noun = one ? singularOf(field) : pluralOf(field);

    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: t.space.md, vertical: t.space.sm + 2),
        decoration: BoxDecoration(
          color: t.accent.warn.withValues(alpha: 0.10),
          border: Border.all(color: t.accent.warn.withValues(alpha: 0.45)),
          borderRadius: t.radius.mdR,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: t.accent.warn),
            SizedBox(width: t.space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count $noun ${one ? 'needs' : 'need'} a $what',
                    style: t.text.bodyStyle.copyWith(
                        color: t.surface.onBase, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Until you choose one, ${one ? 'it stays' : 'they stay'} in '
                    'this list and ${one ? 'does' : 'do'} not appear in '
                    'homeCore. Pick a $what on each row below, then save.',
                    style: t.text.bodySmallStyle
                        .copyWith(color: t.surface.onBaseMuted, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The table's noun, lowercased: "Devices" → "devices".
String pluralOf(CfgField f) =>
    (f.label ?? f.key ?? 'entries').replaceAll('_', ' ').toLowerCase();

/// Naive singularization, which is all a UI noun needs: "Bridges" → "bridge",
/// "Entries" → "entry". A plugin wanting better wording gives the field a label
/// that reads well either way.
String singularOf(CfgField f) {
  final p = pluralOf(f);
  if (p.endsWith('ies') && p.length > 3) {
    return '${p.substring(0, p.length - 3)}y';
  }
  if (p.endsWith('ses') || p.endsWith('xes') || p.endsWith('zes')) {
    return p.substring(0, p.length - 2);
  }
  if (p.endsWith('s') && !p.endsWith('ss')) {
    return p.substring(0, p.length - 1);
  }
  return p;
}
