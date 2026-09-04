import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The device this page's controls are aimed at.
///
/// **A control panel that follows a selection.** John: *"selecting the light
/// which has controls would change the fancy box to provide all of the lights
/// controls, colour wheel etc … essentially replacing the sidebar popout with
/// condensed controls."* A room has four lamps and one set of controls; which
/// lamp they point at is a thing the *viewer* decides, on the page, without
/// editing it.
///
/// The room it was picked in is stored with it, so walking from the Living Room
/// to the Kitchen does not leave the Kitchen's controls aimed at a lamp that is
/// not in it. A page is only ever showing one room, so one holder is enough.
class PickedDevice extends Notifier<({String room, String deviceId})?> {
  @override
  ({String room, String deviceId})? build() => null;

  void pick(String? room, String deviceId) =>
      state = (room: room ?? '', deviceId: deviceId);
}

/// What is picked *for this room*, or null when the pick belongs elsewhere.
///
/// A function over the watched state rather than a method on the notifier:
/// `ref.watch(provider.notifier)` watches the notifier *object*, which never
/// changes, so a reader written that way is told nothing when the pick moves —
/// which is exactly how the first version of this drew a selection ring on
/// nothing and a heading that said "—".
String? pickedIn(({String room, String deviceId})? held, String? room) {
  if (held == null) return null;
  return held.room == (room ?? '') ? held.deviceId : null;
}

final pickedDeviceProvider =
    NotifierProvider<PickedDevice, ({String room, String deviceId})?>(
  PickedDevice.new,
);
