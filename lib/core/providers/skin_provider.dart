import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/skin_resolve.dart';
import '../../design/skins.dart';

/// Public because the picker names it in its own copy, and because a stored
/// skin is a thing worth being able to find by grep.
const kSkinKey = 'skin';

/// The user's skin choice, or null to let each shell pick its own.
///
/// The shells are opinionated by default — Ambient Glass on the wall, Midnight
/// in the hand — and null keeps that, which is a real option rather than an
/// absence: a wall panel and a phone looking different from each other is the
/// design working, not a setting nobody got round to.
///
/// Persisted like the rest of the local UI preferences. A skin is the most
/// visible choice in the app and the last one anyone would want to remake on
/// every reload.
class SkinOverrideNotifier extends Notifier<SkinChoice> {
  @override
  SkinChoice build() {
    _load();
    return const SkinChoice.none();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (ref.mounted) state = SkinChoice.fromStored(p.getString(kSkinKey));
  }

  /// Pick a skin for the whole app, or pass null to hand each shell back its
  /// own default.
  Future<void> choose(SkinChoice skin) async {
    state = skin;
    final p = await SharedPreferences.getInstance();
    // Absent means "no choice", so clearing removes the key rather than
    // storing a sentinel — otherwise the stored value and the default would
    // be two ways of saying the same thing and could drift apart.
    final stored = skin.stored;
    if (stored == null) {
      await p.remove(kSkinKey);
    } else {
      await p.setString(kSkinKey, stored);
    }
  }
}

/// Stored by enum name, which stays readable in the prefs and survives the
/// enum being reordered.
///
/// An unknown name reads as "no choice" rather than throwing. A skin retired in
/// a later version would otherwise leave whoever had chosen it unable to open
/// the app at all — the wrong price for a cosmetic setting.
HcSkin? decodeSkin(String? stored) {
  if (stored == null) return null;
  for (final skin in HcSkin.values) {
    if (skin.name == stored) return skin;
  }
  return null;
}

final skinOverrideProvider = NotifierProvider<SkinOverrideNotifier, SkinChoice>(
    SkinOverrideNotifier.new);
