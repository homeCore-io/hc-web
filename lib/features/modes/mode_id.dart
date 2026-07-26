/// The id a new mode gets, derived from the name its author typed.
///
/// The create dialog used to ask for both — a "Display name" and an "ID (must
/// start with mode_)" — which is asking someone to invent a primary key and
/// then telling them off for getting its prefix wrong. The id is internal: it
/// is what rules store and what nothing ever shows. Deriving it means the only
/// question is what to call the mode.
library;

/// `Guest Room` → `mode_guest_room`.
///
/// Returns an empty string when [displayName] has nothing to slug, which is
/// what the dialog uses to keep Create disabled.
String modeIdFor(String displayName) {
  final slug = displayName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  // "Night Mode" becomes `mode_night`, not `mode_night_mode`. The prefix
  // already says what this is, and the two modes that exist were hand-named
  // exactly this way — a derivation that disagrees with the convention it is
  // replacing would leave the ids looking inconsistent forever.
  final parts =
      slug.split('_').where((p) => p.isNotEmpty && p != 'mode').toList();

  return parts.isEmpty ? '' : 'mode_${parts.join('_')}';
}
