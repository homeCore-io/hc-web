import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/dashboard/builtin_cards.dart';

void main() {
  // The built-in cards go through the same registry a plugin's card would, so
  // there is no privileged path — they just happen to be registered first.
  registerBuiltinDashboardWidgets();

  runApp(const ProviderScope(child: HomecoreApp()));
}
