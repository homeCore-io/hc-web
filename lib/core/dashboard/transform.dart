/// A transform as a *control* expresses it, and as the document stores it.
///
/// Two conversions, and both exist because the two ends disagree on purpose.
/// A slider has to show a number a person can read — degrees, and a percentage
/// — while the document stores degrees and a *fraction*, because every renderer
/// takes a fraction and a document holding 40 while every client divided by 100
/// would be describing the division rather than the value.
///
/// The rule they share is the one worth keeping in a single place: **the
/// neutral value writes nothing at all.** A card at exactly 0° and a card
/// nobody turned are the same picture, and only one of them puts a key in the
/// document and a row in every later diff of it. The same page saved twice by
/// two people who both nudged a slider back to where it started must come out
/// byte-identical.
///
/// Used by the card inspector and the group pane, which had a copy each before
/// this — and a rule about what *not* to write is exactly the kind that rots
/// quietly in the second copy.
library;

/// Degrees from a control, as the document wants them.
double? rotationFromControl(double degrees) => degrees == 0 ? null : degrees;

/// A percentage from a control, as the fraction the document stores.
double? opacityFromControl(double percent) =>
    percent >= 100 ? null : (percent / 100).clamp(0.0, 1.0);

/// The other direction: what a control should show for a stored value.
///
/// Null reads as fully opaque rather than as zero — absent means "not faded",
/// and a slider that opened at 0 for every card nobody had touched would
/// suggest every card was invisible.
double opacityToControl(double? opacity) => (opacity ?? 1) * 100;
