import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/presentation.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/design/hc_icons.dart';

/// A device's icon, and the override that already existed.
///
/// `status_icon` has been in core since long before this arc — stored,
/// PATCHable, round-tripped by the client, documented as *"optional UI-facing
/// status icon override selected by the user"* — and **read by nothing**.
/// There was no way to select one and nothing that would have shown it. So
/// this needed no core change at all, only the half that was missing.
///
/// The distinction that matters is between this and `ui_hint`. A hint changes
/// what the device **is**, so it changes the controls: hint a switch as a light
/// and you get a dimmer it may not have. An icon override changes only the
/// picture — *"this is a switch, and it runs the bathroom fan, so show me a
/// fan"* — and the tile stays honest about what the device can do.

DeviceState _d({String type = 'switch', String? statusIcon, String? uiHint}) =>
    DeviceState(
      id: 'd',
      pluginId: 'plugin.test',
      name: 'Overhead',
      deviceType: type,
      uiHint: uiHint,
      statusIcon: statusIcon,
      available: true,
      state: const {'on': false},
    );

void main() {
  test('with no override it is the device\'s own facet', () {
    expect(deviceIconOverride(_d()), isNull);
    expect(deviceIcon(_d()), HcIcons.forFacet(DeviceFacet.switch_));
  });

  test('an override changes the picture', () {
    final fan = _d(statusIcon: 'fan');
    expect(deviceIconOverride(fan), DeviceFacet.fan);
    expect(deviceIcon(fan), HcIcons.forFacet(DeviceFacet.fan));
  });

  test('and changes nothing else — the device is still a switch', () {
    // The whole reason this is not `ui_hint`. A switch wired to a fan should
    // show a fan and still be a switch, because a fan control it cannot honour
    // is a lie the tile tells.
    final fan = _d(statusIcon: 'fan');
    expect(facetOf(fan, null), DeviceFacet.switch_);
    expect(facetOf(fan, null).isActuator, isTrue);
  });

  test('a ui_hint still moves the facet, as it always did', () {
    final hinted = _d(uiHint: 'light');
    expect(facetOf(hinted, null), DeviceFacet.light);
  });

  test('an override wins over the hint, for the picture only', () {
    final both = _d(uiHint: 'light', statusIcon: 'fan');
    expect(facetOf(both, null), DeviceFacet.light,
        reason: 'the hint still decides what it is');
    expect(deviceIcon(both), HcIcons.forFacet(DeviceFacet.fan),
        reason: 'and the override still decides what it looks like');
  });

  test('an unknown name falls back rather than drawing a blank', () {
    // A device styled by a newer client must not lose its icon.
    for (final raw in ['not_an_icon', '', '   ']) {
      final odd = _d(statusIcon: raw);
      expect(deviceIconOverride(odd), isNull, reason: raw);
      expect(deviceIcon(odd), HcIcons.forFacet(DeviceFacet.switch_));
    }
  });

  test('the stored value is case-insensitive and trimmed', () {
    expect(deviceIconOverride(_d(statusIcon: '  Fan ')), DeviceFacet.fan);
  });

  test('every facet has a storable key, and switch is not a keyword', () {
    final keys = <String>{};
    for (final facet in DeviceFacet.values) {
      expect(facet.iconKey, isNotEmpty, reason: facet.name);
      expect(keys.add(facet.iconKey), isTrue,
          reason: '${facet.iconKey} is claimed twice');
    }
    expect(DeviceFacet.switch_.iconKey, 'switch',
        reason: 'the wire should not carry the language keyword problem');
  });

  test('every key round-trips through the resolver', () {
    for (final facet in DeviceFacet.values) {
      expect(deviceIconOverride(_d(statusIcon: facet.iconKey)), facet,
          reason: facet.iconKey);
    }
  });
}
