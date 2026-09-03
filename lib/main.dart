import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'core/api/asset_fetch.dart';
import 'features/dashboard/builtin_cards.dart';

void main() {
  // **A page's address is its path.**
  //
  // Flutter's default on the web is the hash strategy, so every route lived
  // after a `#` and `/pages/<id>` was not a URL this app had any opinion
  // about: nginx served `index.html` for it (`try_files $uri $uri/
  // /index.html`, which was already right), the app booted, found an empty
  // fragment and went to the house. A link somebody copied out of the address
  // bar took the next person to Home — silently, which is the worst way for a
  // link to fail.
  //
  // Old `#/pages/<id>` links keep working: `app.dart` reads the fragment when
  // there is one and starts there. See `initialLocation`.
  usePathUrlStrategy();

  // The built-in cards go through the same registry a plugin's card would, so
  // there is no privileged path — they just happen to be registered first.
  registerBuiltinDashboardWidgets();

  // The font registry takes its fetcher from outside so tests cannot reach the
  // network. Here is the outside: without this line every custom font silently
  // fails to load, which is exactly how 0.1.36 shipped.
  installAssetFetch();

  runApp(const ProviderScope(child: HomecoreApp()));
}
