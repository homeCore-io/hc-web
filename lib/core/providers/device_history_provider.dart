import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/history_api.dart';
import '../models/history_entry.dart';
import 'auth_provider.dart';

/// One device's recent history, shared by everything in its panel.
///
/// A family provider so it is fetched once per device and cached: the sensor
/// hero's trend line and the History block below it read the same 500 rows
/// rather than asking the server twice for the same answer. `autoDispose` means
/// closing the panel drops it, so opening ten devices does not accumulate ten
/// buffers.
final deviceHistoryProvider =
    FutureProvider.family.autoDispose<List<HistoryEntry>, String>((ref, id) {
  final client = ref.watch(homecoreClientProvider);
  return HistoryApi(client).getHistory(id, limit: 500);
});

/// The numeric points for one attribute, oldest first — the shape a chart wants.
List<HistoryEntry> seriesFor(List<HistoryEntry> all, String attribute) {
  final out = [
    for (final e in all)
      if (e.attribute == attribute && e.value is num) e,
  ]..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
  return out;
}

/// How a metric has moved across [series], as a phrase.
///
/// Deliberately compares against the *oldest point held*, not a fixed window:
/// history is capped at 500 rows, so a chatty sensor's buffer may only reach
/// back an hour while a quiet one reaches back days. Saying "since 09:12" is
/// true in both cases; saying "today" would be a guess in one of them.
({String text, bool rising})? trendOf(List<HistoryEntry> series) {
  if (series.length < 2) return null;
  final first = series.first.value as num;
  final last = series.last.value as num;
  final delta = last - first;
  if (delta.abs() < 0.05) return (text: 'steady', rising: false);

  final at = series.first.recordedAt.toLocal();
  final hh = at.hour.toString().padLeft(2, '0');
  final mm = at.minute.toString().padLeft(2, '0');
  final mag = delta.abs();
  final shown = mag >= 10 ? mag.round().toString() : mag.toStringAsFixed(1);
  // No arrow glyph in the text. ▲/▼ are not in the app's font and rendered as
  // tofu boxes — the direction is carried by [rising], which the caller draws
  // as an icon from a font we actually ship.
  return (text: '$shown since $hh:$mm', rising: delta > 0);
}
