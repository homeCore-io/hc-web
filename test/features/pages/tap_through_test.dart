import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/tap_action.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';

/// **A composed control is layers, and only one of them carries the action.**
///
/// The office page's light chips are four elements each — a ground shape with
/// `on_tap`, a wash over it, an icon and two labels — and the ground is the
/// bottom one. Flutter's `RenderCustomPaint.hitTestSelf` returns *true* by
/// default, so the wash sitting directly on top ate every tap and the chips did
/// nothing at all. John: *"These look like buttons but don't do anything."*
///
/// The rule is that the things you decorate *with* decline the pointer, so a
/// person who stacks a label on a button presses the button.
void main() {
  setUp(() {
    WidgetRegistry.reset();
    registerBuiltinDashboardWidgets();
  });

  test('the things you decorate with let a tap through', () {
    final passes = WidgetRegistry.all
        .where((d) => d.passesTaps)
        .map((d) => d.type)
        .toSet();
    expect(
      passes,
      {
        'shape',
        'line',
        'text',
        'icon',
        'image',
        'heading',
        'divider',
        'spacer'
      },
      reason: 'a decoration that eats a tap breaks every composed control '
          'built under it',
    );
  });

  test('nothing with behaviour of its own gives its pointer away', () {
    // The inverse is the dangerous direction: marking a control here makes it
    // untouchable, which looks exactly like the bug this flag exists to fix.
    for (final type in [
      'toggle',
      'slider',
      'stepper',
      'colour_wheel',
      'warmth',
      'scene_button',
      'keypad',
      'thermostat',
      'device_tile',
      'media_player',
      'room_field',
      'device_list',
      'scene_row',
      'mode_chips'
    ]) {
      final d = WidgetRegistry.lookup(type);
      expect(d, isNotNull, reason: '$type is not registered');
      expect(d!.passesTaps, isFalse, reason: '$type would be untappable');
    }
  });

  test('an action of its own outranks the flag', () {
    // The chip's ground is a shape — a type that passes taps — and it is the
    // element carrying `on_tap`. It has to keep it.
    final ground = {
      'shape': 'rectangle',
      'on_tap': {'do': 'set', 'target': 'lamp', 'attribute': 'on'},
    };
    expect(WidgetRegistry.lookup('shape')!.passesTaps, isTrue);
    expect(TapAction.fromConfig(ground), isNotNull,
        reason: 'the wrap only stands down when there is no action to keep');
    expect(TapAction.fromConfig(const {'shape': 'rectangle'}), isNull);
  });
}
