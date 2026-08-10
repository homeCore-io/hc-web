import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/api/asset_fetch.dart';
import 'features/dashboard/builtin_cards.dart';

void main() {
  // The built-in cards go through the same registry a plugin's card would, so
  // there is no privileged path — they just happen to be registered first.
  registerBuiltinDashboardWidgets();

  // The font registry takes its fetcher from outside so tests cannot reach the
  // network. Here is the outside: without this line every custom font silently
  // fails to load, which is exactly how 0.1.36 shipped.
  installAssetFetch();

  runApp(const ProviderScope(child: HomecoreApp()));
}
