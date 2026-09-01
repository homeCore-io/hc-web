import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/binding.dart';
import '../../core/dashboard/card_style.dart';
import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';

/// The facet names an icon element may be pinned to.
///
/// The same vocabulary `status_icon` uses, and for the reason that field's own
/// comment gives: every value already has artwork and a skin already reaches
/// it. Sorted so the picker is a list a person can scan rather than the order
/// the enum happens to be declared in.
final List<String> kIconFacets = () {
  final names = [
    for (final f in DeviceFacet.values)
      if (f != DeviceFacet.unknown) f.name,
  ]..sort();
  return List<String>.unmodifiable(names);
}();

/// One device, drawn as its own symbol.
///
/// **The icon is a function of what the device IS**, never of which plugin owns
/// it — `deviceIcon` has answered that question for the rest of the app for a
/// while, and this is the first element to ask it. Pinning a facet overrides
/// the answer without changing the device, which is the same split
/// `status_icon` makes: the picture changes, what the thing can do does not.
///
/// State lives in the glyph's weight as well as its colour, because Phosphor
/// has a weight axis and `HcIcons` was chosen for it. An icon that only changed
/// colour would be illegible to anyone who cannot separate the two.
class IconElement extends ConsumerWidget {
  const IconElement({super.key, required this.config});

  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value;

    final id = (config['device_id'] as String? ?? '').trim();
    final device = devices == null || id.isEmpty
        ? null
        : devices.where((d) => d.id == id).cast<DeviceState?>().firstOrNull;

    DeviceState? lookup(String wanted) =>
        devices?.where((d) => d.id == wanted).cast<DeviceState?>().firstOrNull;

    final bindings = Bindings.fromConfig(config);
    final on = device != null && isOn(device);

    // A pinned facet wins; otherwise the device answers. With neither there is
    // still something to draw — the element validates against that case, but a
    // document written by hand can always arrive without it.
    final pinned = _facet(config['facet']);
    final glyph = pinned != null
        ? HcIcons.forFacet(pinned, on: on)
        : device != null
            ? deviceIcon(device, on: on)
            : HcIcons.forFacet(DeviceFacet.unknown);

    // The bound colour beats the authored one, and the authored one beats the
    // default — the same order every styled thing in this app resolves in.
    final bound = bindings.resolve('color', lookup);
    final ink = resolveInk(t, bound is String ? bound : null) ??
        resolveInk(t, config['ink'] as String?) ??
        (on ? t.accent.active : t.surface.onBaseMuted);

    final rotation = bindings.resolve('rotation', lookup);
    final opacity = bindings.resolve('opacity', lookup);

    return LayoutBuilder(
      builder: (context, c) {
        // The glyph takes the cell, less a margin when it sits on a disc. Sized
        // from the box rather than from a font-size field, because an element
        // you drag out to a size should be that size.
        final side = c.biggest.shortestSide;
        final backing = config['backing'] == true;
        final glyphSize = backing ? side * .52 : side * .8;

        Widget out = Icon(glyph, size: glyphSize, color: ink);

        if (backing) {
          out = DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ink.withValues(alpha: .16),
            ),
            child: Center(child: out),
          );
        } else {
          out = Center(child: out);
        }

        if (rotation is double && rotation != 0) {
          out = Transform.rotate(
              angle: rotation * 3.1415926535 / 180, child: out);
        }
        if (opacity is double) {
          out = Opacity(opacity: opacity.clamp(0.0, 1.0), child: out);
        }

        // Unavailable is said, not implied. A device that has gone quiet drawn
        // at full strength is a dashboard lying about the house.
        if (device != null && !device.available) {
          out = Opacity(opacity: .4, child: out);
        }
        return SizedBox.expand(child: out);
      },
    );
  }

  static DeviceFacet? _facet(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    for (final f in DeviceFacet.values) {
      if (f.name == raw) return f;
    }
    // An unknown name falls back rather than drawing a blank, because a page
    // from a newer client must not lose its icon.
    return null;
  }
}
