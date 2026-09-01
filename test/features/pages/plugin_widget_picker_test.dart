import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/plugin_render.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/providers/dashboard_vocabulary_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/widget_config_form.dart';

/// Choosing a plugin card, rather than typing two ids from memory.
///
/// `plugin_widget` carries its identity in its config — `plugin_id` and
/// `widget_id` — and until core could enumerate plugin widgets there was
/// nothing to offer, so the form asked for both as free text. Now the
/// vocabulary knows every plugin card on the installation, including its title,
/// and the ids are a thing to choose rather than a thing to remember.
PluginWidgetSpec _spec(String plugin, String widget, String title) =>
    PluginWidgetSpec.fromJson({
      'plugin_id': plugin,
      'widget_id': widget,
      'title': title,
      'render': {'kind': 'gauge', 'value': 'flow'},
    })!;

Future<Map<String, dynamic>> _pump(
  WidgetTester tester, {
  required List<PluginWidgetSpec>? vocabulary,
  Map<String, dynamic> initial = const {},
}) async {
  registerBuiltinDashboardWidgets();
  final config = <String, dynamic>{...initial};
  await tester.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(ProviderScope(
    overrides: [
      dashboardVocabularyProvider.overrideWith((ref) async => vocabulary),
    ],
    child: MaterialApp(
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => WidgetConfigForm(
              descriptor: WidgetRegistry.lookup(pluginWidgetType)!,
              initial: config,
              onChanged: (c) => setState(() => config
                ..clear()
                ..addAll(c)),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return config;
}

void main() {
  final catalogue = [
    _spec('boiler', 'boiler_flow', 'Boiler flow'),
    _spec('boiler', 'boiler_temp', 'Boiler temperature'),
    _spec('solar', 'solar_yield', 'Solar yield'),
  ];

  testWidgets('the plugins offering cards are the ones you can choose from',
      (tester) async {
    await _pump(tester, vocabulary: catalogue);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();

    expect(find.text('boiler'), findsWidgets);
    expect(find.text('solar'), findsWidgets);
  });

  testWidgets('cards are listed by title, and only that plugin\'s',
      (tester) async {
    // `boiler_flow` is what the plugin author typed; "Boiler flow" is what they
    // meant. The id is still what gets stored, because it is what core
    // validates against.
    await _pump(
      tester,
      vocabulary: catalogue,
      initial: const {'plugin_id': 'boiler'},
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();

    expect(find.text('Boiler flow'), findsWidgets);
    expect(find.text('Boiler temperature'), findsWidgets);
    expect(find.text('Solar yield'), findsNothing);
  });

  testWidgets('choosing a card stores its id, not its title', (tester) async {
    final config = await _pump(
      tester,
      vocabulary: catalogue,
      initial: const {'plugin_id': 'boiler'},
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Boiler temperature').last);
    await tester.pumpAndSettle();

    expect(config['widget_id'], 'boiler_temp');
  });

  testWidgets('changing the plugin clears the card', (tester) async {
    // The card that was chosen belongs to the plugin that was chosen. Leaving
    // it behind would name a card the new plugin does not have, and core would
    // accept it — `plugin_widget`'s two ids are strings it does not resolve.
    final config = await _pump(
      tester,
      vocabulary: catalogue,
      initial: const {'plugin_id': 'boiler', 'widget_id': 'boiler_flow'},
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('solar').last);
    await tester.pumpAndSettle();

    expect(config['plugin_id'], 'solar');
    expect(config.containsKey('widget_id'), isFalse);
  });

  testWidgets('with no plugin chosen, the card list says so rather than being '
      'an empty menu', (tester) async {
    await _pump(tester, vocabulary: catalogue);
    expect(find.text('Choose a plugin first.'), findsOneWidget);
  });

  testWidgets('a plugin contributing nothing is said, not shown as empty',
      (tester) async {
    // The plugin was chosen and has since stopped publishing. An empty dropdown
    // would read as "this app is broken" rather than "that plugin is gone".
    await _pump(
      tester,
      vocabulary: catalogue,
      initial: const {'plugin_id': 'furnace'},
    );
    expect(find.textContaining('contributes no cards'), findsOneWidget);
  });

  testWidgets('a core that cannot be asked leaves the ids typeable',
      (tester) async {
    // Upgrading core must not become a prerequisite for fixing a typo in a card
    // that already exists.
    await _pump(tester, vocabulary: null);

    expect(find.textContaining('type the id by hand'), findsNWidgets(2));
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });
}
