/// The id a new helper gets, derived from its kind and the name typed.
///
/// The hub prefixes by type — `timer_`, `switch_`, `counter_` — and adds the
/// prefix itself if the id arrives without one. Deriving it here means the
/// create dialog can show what the id will be before anything is sent, and can
/// refuse a clash without a round trip.
library;

String glueIdFor(String type, String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  // "Bathroom Timer" under the timer kind becomes `timer_bathroom`, not
  // `timer_bathroom_timer` — the prefix already says what it is, and the
  // helpers that exist were hand-named exactly that way.
  final parts =
      slug.split('_').where((p) => p.isNotEmpty && p != type).toList();

  return parts.isEmpty ? '' : '${type}_${parts.join('_')}';
}
