import 'package:flutter/material.dart';

import '../tokens.dart';

/// A line of prose with editable chips inline.
///
/// The whole redesign rests on this: a rule reads as a sentence about your house
/// — "when the **Bathroom Door Sensor** **closes**" — instead of nine labelled
/// boxes, six of them empty. Words are [Text]; the editable parts are [HcChip]s
/// dropped straight into the flow.
///
/// It is a [Wrap], not a [Row], so a long sentence breaks like a sentence
/// instead of overflowing. Chips are baseline-ish aligned to the words around
/// them, which is what stops the whole thing reading as a toolbar.
class HcSentence extends StatelessWidget {
  const HcSentence({
    super.key,
    required this.parts,
    this.size = HcSentenceSize.normal,
  });

  /// Mix plain [String]s (rendered as prose) and widgets (usually [HcChip]).
  /// A String is a word; anything else is a control.
  final List<Object> parts;

  final HcSentenceSize size;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    // A local scale, not the ramp. The sentence editor sets prose at three
    // sizes chosen against each other — the ramp's roles are for chrome and
    // would flatten the difference between a rule's headline and its clauses.
    // If it ever wants tokens it wants a `prose` role, not these seven.
    final fontSize = switch (size) {
      HcSentenceSize.large => 21.0,
      HcSentenceSize.normal => 17.0,
      HcSentenceSize.small => 15.0,
    };

    final prose = TextStyle(
      fontSize: fontSize,
      height: 1.6,
      letterSpacing: -0.1,
      // The connective words recede; the chips are what you look at.
      color: t.surface.onBaseMuted,
      fontWeight: FontWeight.w400,
    );

    return Wrap(
      spacing: t.space.xs + 2,
      runSpacing: t.space.xs + 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final part in parts)
          if (part is String)
            Text(part, style: prose)
          else if (part is Widget)
            part,
      ],
    );
  }
}

enum HcSentenceSize { small, normal, large }

/// A labelled clause with a rail down its left edge — WHEN / ONLY IF / THEN.
///
/// The rail is a wire: a vertical line joining the clauses, with a node at each
/// one. When a clause is currently *true* (the trigger's device is in the state
/// the rule waits for), its node lights. So the rule shows you where the house
/// actually is, standing still.
class HcClause extends StatelessWidget {
  const HcClause({
    super.key,
    required this.label,
    required this.child,
    this.live = false,
    this.last = false,
  });

  final String label;
  final Widget child;

  /// Lights the rail node. Wire this to the real evaluation, not to a guess.
  final bool live;

  /// Suppresses the wire below the final clause, so it terminates rather than
  /// trailing into nothing.
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 78,
            child: Padding(
              padding: EdgeInsets.only(top: t.space.md + 2, right: t.space.sm),
              child: Text(
                label.toUpperCase(),
                textAlign: TextAlign.right,
                style: t.text.overlineStyle.copyWith(
                  fontWeight: FontWeight.w700,
                  // Wider than the ramp: this label sits in its own right
                  // aligned column, and the extra tracking is what holds it
                  // apart from the sentence beside it.
                  letterSpacing: 1.8,
                  color: t.surface.onBaseMuted,
                ),
              ),
            ),
          ),
          _Rail(live: live, last: last),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                t.space.md,
                t.space.md,
                0,
                t.space.lg,
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.live, required this.last});

  final bool live;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return SizedBox(
      width: 9,
      child: Column(
        children: [
          SizedBox(height: t.space.md + 1),
          AnimatedContainer(
            duration: t.motion.d(t.motion.base),
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: live ? t.accent.active : t.surface.base,
              border: Border.all(
                color: live ? t.accent.active : t.surface.onBaseMuted,
              ),
              boxShadow: [
                if (live && t.glow.enabled)
                  BoxShadow(
                    color: t.accent.active.withValues(alpha: 0.6),
                    blurRadius: 12,
                  ),
              ],
            ),
          ),
          if (!last)
            Expanded(
              child: Container(width: 1, color: t.stroke.hairline),
            ),
        ],
      ),
    );
  }
}
