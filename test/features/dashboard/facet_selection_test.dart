import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/devices/presentation.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/devices/device_query.dart';

/// `selection_mode: facet` — "every light in the house", as a kind.
///
/// Phase 10 of `designer-plan.md`, and one of only two core changes in the
/// whole programme. It was deferred for a long time on purpose: the house's own
/// "Lights 22" is facet-derived, and the nearest storable selection was
/// `query: "light"`, which matches on the **name**. On a real house that found
/// 17 of the 22 — a card confidently short by five, which is worse than no
/// card.
///
/// So the tests that matter here are the ones that pin the *counts*: what the
/// library says, what the card selects, and what a name-search would have said
/// instead.

DeviceState _d(
  String id, {
  String type = 'light',
  Map<String, dynamic>? state,
  String? name,
}) =>
    DeviceState(
      id: id,
      pluginId: 'plugin.test',
      name: name ?? id,
      deviceType: type,
      available: true,
      state: state ?? const {'on': false},
    );

/// A house whose lights are not all called "light".
///
/// This is the shape that made the query approach wrong: three of the five are
/// lights by *kind* while carrying a device type and a name a substring search
/// never reaches.
final _house = [
  _d('l1', name: 'Ceiling light'),
  _d('l2', type: 'dimmer', name: 'Hall dimmer', state: {'on': true}),
  _d('l3', type: 'light_rgb', name: 'Lamp'),
  _d('l4', type: 'hue_light', name: 'Sconce'),
  _d('lock1', type: 'lock', name: 'Front door'),
  _d('t1', type: 'temperature_sensor', name: 'Hall temp'),
];

void main() {
  group('grouping', () {
    test('the kinds a person sees are the kinds a card can store', () {
      // The label on /devices and the key in a card's config come from one
      // enum now — they used to be one `switch` that only produced labels, and
      // a second list of keys would have been free to drift from it.
      expect(facetGroupOf(DeviceFacet.light), DeviceFacetGroup.lights);
      expect(facetGroupOf(DeviceFacet.dimmableLight), DeviceFacetGroup.lights);
      expect(facetGroupOf(DeviceFacet.colorLight), DeviceFacetGroup.lights);
      expect(DeviceFacet.colorLight.label, 'Lights');
      expect(DeviceFacetGroup.lights.key, 'lights');
    });

    test('every facet lands in a group', () {
      for (final facet in DeviceFacet.values) {
        expect(() => facetGroupOf(facet), returnsNormally, reason: facet.name);
      }
    });

    test('a key round-trips', () {
      for (final group in DeviceFacetGroup.values) {
        expect(DeviceFacetGroup.fromKey(group.key), group);
      }
      expect(DeviceFacetGroup.fromKey('not_a_kind'), isNull);
      expect(DeviceFacetGroup.fromKey(null), isNull);
    });
  });

  group('selection', () {
    test('selects the whole kind, not just the facet spelled that way', () {
      final selection = selectDevicesWithCount(
          _house, {'selection_mode': 'facet', 'facet': 'lights'});
      expect(selection.matched, 4,
          reason: 'a plain light, a dimmer, a colour light and a hue light — '
              'all four are lights to the person looking at them');
    });

    test('which is more than the search it replaces would have found', () {
      // The whole reason the mode exists, stated as a number.
      final byQuery = selectDevicesWithCount(
          _house, {'selection_mode': 'query', 'query': 'light'});
      expect(byQuery.matched, lessThan(4));
    });

    test('a different kind selects only its own', () {
      expect(
          selectDevicesWithCount(
              _house, {'selection_mode': 'facet', 'facet': 'locks'}).matched,
          1);
      expect(
          selectDevicesWithCount(
                  _house, {'selection_mode': 'facet', 'facet': 'environment'})
              .matched,
          1);
    });

    test('a kind nobody has selects nothing', () {
      expect(
          selectDevicesWithCount(
              _house, {'selection_mode': 'facet', 'facet': 'sirens'}).matched,
          0);
    });

    test('an unknown kind selects nothing, not everything', () {
      // Core validates the shape and not the vocabulary — it cannot compute
      // facets — so a card written by a newer client can name a kind this
      // build has never heard of. Falling through to "no filter" would show
      // the whole house under a heading that says otherwise.
      for (final facet in ['facets_from_the_future', '']) {
        expect(
            selectDevicesWithCount(
                _house, {'selection_mode': 'facet', 'facet': facet}).matched,
            0,
            reason: facet);
      }
    });
  });

  group('the contract with core', () {
    test('a facet card must name a facet, exactly as core requires', () {
      registerBuiltinDashboardWidgets();
      final validate = WidgetRegistry.lookup('device_grid')!.validate!;
      // Core rejects the whole dashboard on the first invalid widget, so this
      // has to mirror `validate_selection_widget_config` and not merely
      // resemble it.
      expect(validate({'selection_mode': 'facet'}), isNotNull);
      expect(validate({'selection_mode': 'facet', 'facet': ''}), isNotNull);
      expect(validate({'selection_mode': 'facet', 'facet': '   '}), isNotNull);
      expect(validate({'selection_mode': 'facet', 'facet': 'lights'}), isNull);
    });

    test('and the mode itself is now an accepted one', () {
      registerBuiltinDashboardWidgets();
      final field = WidgetRegistry.lookup('device_grid')!
          .configFields
          .firstWhere((f) => f.name == 'selection_mode');
      expect(field.options, ['manual', 'area', 'query', 'facet']);
    });
  });
}
