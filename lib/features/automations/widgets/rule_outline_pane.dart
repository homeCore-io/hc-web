import 'package:flutter/material.dart';

import '../../../core/rules/rule.dart';
import '../../../design/tokens.dart';
import '../rule_outline.dart';
import 'editor_style.dart';
import 'rule_refs.dart';

/// The rule as an outline — read-only, shown beside the editor for comparison.
///
/// This is the first slice of the outline-and-inspector direction, deliberately
/// with no editing in it. The question it exists to answer is whether an
/// outline reads a real rule better than the tree does; putting them side by
/// side answers that on live rules, which no mockup can.
///
/// Depth is a coloured guide line per level rather than indentation alone —
/// three levels in (a branch arm inside a loop) is exactly where indentation
/// stops being legible, and that is the case this direction has to win.
class RuleOutlinePane extends StatelessWidget {
  const RuleOutlinePane({super.key, required this.rule, required this.refs});

  final HcRule rule;
  final RuleRefs refs;

  /// One colour per nesting level, matching the tree's own rail palette so the
  /// two panes describe the same rule in the same terms.
  static const _depth = [
    Color(0xFF6C8CFF),
    Color(0xFF34C7A6),
    Color(0xFFE0A33D),
    Color(0xFFD46FA8),
    Color(0xFF9D7BE0),
  ];

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final rows = outlineRows(rule,
        labelFor: refs.labelFor, schemas: refs.schemaFor);

    final children = <Widget>[];
    OutlineClause? clause;
    for (final row in rows) {
      if (row.clause != clause) {
        clause = row.clause;
        children.add(Padding(
          padding: EdgeInsets.fromLTRB(2, t.space.md, 0, t.space.xs),
          child: Row(children: [
            // The clause carries the colour. Nesting colour only appears where
            // there IS nesting, and most real rules are flat — without this the
            // pane reads as grey text on a rule that is doing plenty.
            Container(
              width: 3,
              height: 11,
              margin: const EdgeInsets.only(right: 7),
              decoration: BoxDecoration(
                color: _clauseColor(clause),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              switch (clause) {
                OutlineClause.when => 'WHEN',
                OutlineClause.ifClause => 'AND IF',
                OutlineClause.then => 'THEN',
              },
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: _clauseColor(clause),
              ),
            ),
          ]),
        ));
      }
      children.add(_row(t, row, _clauseColor(row.clause)));
    }

    return Container(
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: t.radius.smR,
        border: Border.all(color: t.stroke.hairline),
      ),
      padding: EdgeInsets.fromLTRB(t.space.sm, t.space.xs, t.space.sm, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The heading stays put; only the rule scrolls. A long rule otherwise
          // scrolls its own title away, and the pane loses the one label that
          // says it is a preview rather than a second editor.
          Padding(
            padding: EdgeInsets.only(top: t.space.xs, bottom: t.space.xs),
            child: Row(children: [
              Icon(Icons.account_tree_outlined,
                  size: 14, color: t.surface.onBaseMuted),
              SizedBox(width: t.space.xs),
              const RailLabel('Outline'),
              const Spacer(),
              Text('read-only preview',
                  style: TextStyle(fontSize: 10.5, color: t.surface.onBaseMuted)),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: t.space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One colour per clause — the same three the editor's own rails use, so a
  /// glance at either pane says which part of the rule you are reading.
  static Color _clauseColor(OutlineClause c) => switch (c) {
        OutlineClause.when => _depth[0],
        OutlineClause.ifClause => _depth[1],
        OutlineClause.then => _depth[2],
      };

  Widget _row(HcTokens t, OutlineRow row, Color clause) {
    final muted = t.surface.onBaseMuted;
    final isStructure =
        row.kind == OutlineKind.container || row.kind == OutlineKind.arm;

    // One guide line per level the row sits under, coloured by that level.
    final guides = <Widget>[];
    for (var d = 0; d < row.depth; d++) {
      guides.add(Container(
        width: 13,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: _depth[d % _depth.length].withValues(alpha: 0.45),
            ),
          ),
        ),
      ));
    }

    return Opacity(
      opacity: row.enabled ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Every row hangs off its clause's rail, so the three parts of the
            // rule stay distinguishable even with no nesting anywhere.
            Container(
              width: 3,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: clause.withValues(alpha: 0.28)),
                ),
              ),
            ),
            ...guides,
            SizedBox(width: t.space.xs),
            Expanded(
              child: Row(children: [
                if (row.ordinal != null && row.kind != OutlineKind.arm) ...[
                  SizedBox(
                    width: 16,
                    child: Text('${row.ordinal}',
                        style: TextStyle(
                            fontSize: 10.5,
                            color: muted.withValues(alpha: 0.55),
                            fontFeatures: t.numericFontFeatures)),
                  ),
                ],
                if (row.keyword != null) ...[
                  Text(row.keyword!.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                        color: isStructure
                            ? _depth[(row.depth + 1) % _depth.length]
                            : muted,
                      )),
                  if (row.label.isNotEmpty) SizedBox(width: t.space.xs),
                ],
                if (row.label.isNotEmpty)
                  Expanded(
                    child: Text(
                      row.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: row.kind == OutlineKind.step ||
                                row.kind == OutlineKind.condition ||
                                row.kind == OutlineKind.trigger
                            ? t.surface.onBase
                            : muted,
                        decoration:
                            row.enabled ? null : TextDecoration.lineThrough,
                      ),
                    ),
                  )
                else
                  const Spacer(),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
