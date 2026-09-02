import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/design_tools.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/card_library.dart';

/// **A widget this app can draw and nobody can place is not a feature.**
///
/// This test exists because seven of them shipped. The icon element, the
/// switch, the slider, the scene button, the colour wheel, the warmth bar and
/// the stepper were registered, declared in core's vocabulary, covered by
/// tests, and reachable from nothing: the tool rail did not offer them and the
/// catalogue is a hand-written list nobody had added them to. Opening the
/// designer after a release of that work showed a page identical to the one
/// before it, because it was identical.
///
/// It is the same failure the dashboard vocabulary prevents between core and
/// this client — two hand-kept lists of the same set — happening inside this
/// client, where nothing was watching.
void main() {
  setUp(() {
    WidgetRegistry.reset();
    registerBuiltinDashboardWidgets();
  });

  /// Types that are deliberately not offered, with the reason. Anything not
  /// named here and not placeable is a bug.
  const unplaceable = {
    // A plugin's card. It is placed by picking the plugin's widget, not by
    // choosing the wrapper type — core validates `plugin_id` and `widget_id`
    // and an empty one names no plugin at all.
    'plugin_widget',
  };

  test('every widget this app can draw can be put on a page', () {
    final placeable = {
      ...CardLibrary.offeredTypes,
      for (final tool in DesignTool.values)
        if (tool.type != null) tool.type!,
    };

    final unreachable = WidgetRegistry.all
        .map((d) => d.type)
        .where((t) => !placeable.contains(t) && !unplaceable.contains(t))
        .toList()
      ..sort();

    expect(
      unreachable,
      isEmpty,
      reason: 'these are registered and drawable and there is no way to put '
          'one on a page — not a tool, not a catalogue entry. Add one, or name '
          'it in `unplaceable` with why.',
    );
  });

  test('every tool and every catalogue entry makes something real', () {
    // The other direction: an entry naming a type nothing draws puts an
    // unknown-card placeholder on the page, which reads as the app being
    // broken rather than as a typo in a list.
    for (final tool in DesignTool.values) {
      if (tool.type == null) continue;
      expect(WidgetRegistry.knows(tool.type!), isTrue,
          reason: '${tool.name} draws a "${tool.type}" and nothing renders it');
    }
    for (final type in CardLibrary.offeredTypes) {
      expect(WidgetRegistry.knows(type), isTrue,
          reason: 'the catalogue offers "$type" and nothing renders it');
    }
  });

  test('the controls that set the house are all reachable', () {
    // Named outright rather than counted, for the same reason core's element
    // family is: a count passes the moment anybody adds anything, which is
    // exactly how these went missing.
    final placeable = {
      ...CardLibrary.offeredTypes,
      for (final tool in DesignTool.values)
        if (tool.type != null) tool.type!,
    };
    for (final type in [
      'icon',
      'toggle',
      'slider',
      'stepper',
      'colour_wheel',
      'warmth',
      'scene_button',
    ]) {
      expect(placeable, contains(type));
    }
  });

  test('the rail bands the tools, and the band that sets is not empty', () {
    // The whole argument of the redesign: there are three kinds of thing you
    // can put on a page, and the one that changes the house had no tools.
    final setters =
        DesignTool.values.where((t) => t.band == ToolBand.set_).toList();
    expect(setters, isNotEmpty);
    for (final tool in setters) {
      expect(tool.type, isNotNull, reason: '${tool.name} must make something');
    }
  });
}
