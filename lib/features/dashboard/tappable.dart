import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dashboard/tap_action.dart';
import '../../core/devices/scene_state.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/modes_provider.dart';
import '../../core/providers/page_room_provider.dart';
import '../../core/providers/picked_device_provider.dart';
import '../../core/providers/scenes_provider.dart';
import '../../core/schema/device_schema.dart';
import '../devices/device_sheet.dart';

/// Makes any drawn element do something when it is touched.
///
/// Wrapped once, at the single seam where a placement becomes a widget, so an
/// element does not have to opt in — see `page_grid.dart`. That is the whole
/// point of `on_tap` being a property: a shape, an icon, a text label and a
/// photograph all get it without any of them knowing about it.
///
/// **Nothing here is new machinery.** Each action is a call this app already
/// makes from another surface, and a tap is one more caller: `activateScene`
/// (or `activate` on a plugin scene-device), `setModeOn`, and
/// `DevicesNotifier.command`, which already applies optimistically and rolls
/// back with the rest of the app's opinion about what the house is doing.
class Tappable extends ConsumerWidget {
  const Tappable({
    super.key,
    required this.config,
    required this.editing,
    required this.child,
  });

  final Map<String, dynamic> config;

  /// True in the designer, where a tap **selects** rather than runs.
  ///
  /// Load-bearing: an action that fired while somebody was arranging the page
  /// would turn the lights off every time they picked the element up, and they
  /// would have no way to select it at all.
  final bool editing;

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = TapAction.fromConfig(config);
    if (action == null || editing) return child;

    final live = _live(ref, action);

    return Semantics(
      // Said outright. An element that does something and does not say so is
      // invisible to a screen reader, and one that says so and does nothing is
      // worse — so the flag and the callback are decided together, once.
      button: true,
      enabled: live,
      child: MouseRegion(
        cursor: live ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          // Opaque, so the element's whole box is the target. A shape with a
          // transparent fill would otherwise be tappable only on its border.
          behavior: HitTestBehavior.opaque,
          onTap: live ? () => _run(context, ref, action) : null,
          child: Opacity(
            // An action whose target is gone looks inert rather than broken —
            // the same distinction the scene button draws. A control that looks
            // live and does nothing teaches somebody the house is broken.
            opacity: live ? 1 : .4,
            child: child,
          ),
        ),
      ),
    );
  }

  /// Whether this action can actually do anything right now.
  ///
  /// Checked at build AND acted on at tap, because the answer changes: a device
  /// can re-register between the page being drawn and somebody touching it.
  bool _live(WidgetRef ref, TapAction action) {
    if (!action.isComplete) return false;
    final id = action.targetId!;
    switch (action.action) {
      case TapDo.scene:
        final devices = ref.watch(devicesProvider).value;
        final native = ref.watch(scenesProvider).value;
        return (native?.any((s) => s.id == id) ?? false) ||
            (devices?.any((d) => d.id == id && isSceneDevice(d)) ?? false);
      case TapDo.mode:
        return ref.watch(modesProvider).value?.any((m) => m.id == id) ?? false;
      case TapDo.set:
        final device = ref
            .watch(devicesProvider)
            .value
            ?.where((d) => d.id == id)
            .cast<DeviceState?>()
            .firstOrNull;
        return device != null && device.available && _accepts(device, action);
      case TapDo.pick:
        // Only that it is here. Aiming is a page-local act — nothing is sent,
        // so nothing can be refused.
        return ref.watch(devicesProvider).value?.any((d) => d.id == id) ??
            false;
      case TapDo.device:
        // Only that the device is here. The sheet is a *view* of whatever it
        // can do, so unlike `set` there is no particular attribute to promise
        // — and it stays worth opening on a device that is offline, which is
        // often when you most want to look at one.
        return ref.watch(devicesProvider).value?.any((d) => d.id == id) ??
            false;
      case TapDo.page:
        // Not checked against the dashboard list: a page can be created after
        // this one was drawn, and refusing to navigate because this client has
        // not listed it yet would be worse than a route that says "not found".
        return true;
    }
  }

  /// Did the plugin promise this write?
  ///
  /// The switch's rule, unchanged — only a registered schema counts. An
  /// inferred `writable` is this app's opinion, and `hc-sonos::execute_command`
  /// rejects attribute-style writes outright, so a tap built on the guess would
  /// look right, send, and change nothing. See `schema/attribute_policy.dart`.
  static bool _accepts(DeviceState device, TapAction action) {
    final spec = device.schema?.attributes[action.attribute];
    if (spec == null || !spec.writable) return false;
    // Flipping only means anything for a boolean. A tap that "toggles" a
    // brightness has no second state to go to.
    if (action.toggles) return spec.kind == AttributeKind.bool_;
    return true;
  }

  Future<void> _run(
      BuildContext context, WidgetRef ref, TapAction action) async {
    final id = action.targetId!;
    switch (action.action) {
      case TapDo.scene:
        // The two kinds are not interchangeable — a plugin scene is a device
        // and takes `activate`; a native one is a POST to /scenes. Sending one
        // down the other's path fails silently.
        final plugin = ref
            .read(devicesProvider)
            .value
            ?.where((d) => d.id == id && isSceneDevice(d))
            .cast<DeviceState?>()
            .firstOrNull;
        if (plugin != null) {
          await ref
              .read(devicesApiProvider)
              .setDeviceState(id, {'activate': true});
        } else {
          await ref.read(scenesApiProvider).activateScene(id);
        }
      case TapDo.mode:
        final now =
            ref.read(modesProvider).value?.where((m) => m.id == id).firstOrNull;
        final to = action.value is bool
            ? action.value! as bool
            // Flip what it is now. A mode button that could only turn a mode on
            // is half a control.
            : !(now?.on ?? false);
        await ref.read(modesApiProvider).setModeOn(id, to);
      case TapDo.set:
        final device = ref
            .read(devicesProvider)
            .value
            ?.where((d) => d.id == id)
            .cast<DeviceState?>()
            .firstOrNull;
        // Re-checked here, not only at build: a device can re-register between
        // the page being drawn and this tap.
        if (device == null || !_accepts(device, action)) return;
        final value = action.toggles
            ? device.state[action.attribute] != true
            : action.value;
        await ref
            .read(devicesProvider.notifier)
            .command(id, {action.attribute!: value});
      case TapDo.pick:
        ref
            .read(pickedDeviceProvider.notifier)
            .pick(ref.read(pageRoomProvider), id);
      case TapDo.device:
        if (!context.mounted) return;
        showDeviceSheet(context, id);
      case TapDo.page:
        if (!context.mounted) return;
        context.go('/dashboards/$id');
    }
  }
}
