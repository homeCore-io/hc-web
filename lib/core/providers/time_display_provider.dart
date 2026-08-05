import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kUtcKey = 'time_display_utc';

class TimeDisplayNotifier extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (ref.mounted) state = p.getBool(_kUtcKey) ?? false;
  }

  Future<void> toggle() async {
    state = !state;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kUtcKey, state);
  }
}

final timeUtcProvider = NotifierProvider<TimeDisplayNotifier, bool>(
  TimeDisplayNotifier.new,
);

/// Format a DateTime for display. Pass [utc]=true for UTC, false for local.
/// If [showDate]=true includes month/day prefix.
String fmtTime(DateTime dt, {required bool utc, bool showDate = false}) {
  final t = utc ? dt.toUtc() : dt.toLocal();
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  final s = t.second.toString().padLeft(2, '0');
  final sfx = utc ? 'Z' : '';
  if (showDate) return '${t.month}/${t.day} $h:$m$sfx';
  return '$h:$m:$s$sfx';
}
