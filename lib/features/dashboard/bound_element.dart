import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/binding.dart';
import '../../core/dashboard/widget_registry.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';

/// Hands an element its config with the house's answers already in it.
///
/// **A bindable property name IS a config key**, so a binding resolves into the
/// map the element already reads and the drawing code needs no idea that
/// devices exist. `ShapePrimitiveCard` and `TextPrimitiveCard` were written
/// before any of this and are untouched by it.
///
/// That rule is the whole design. It also decides the units: a binding onto
/// shape's `opacity` writes 0–100 because that is what the field means there.
/// One canonical unit per property *name* across every element would have made
/// the same word mean different things depending on which element it was
/// written on.
class BoundElement extends ConsumerWidget {
  const BoundElement({
    super.key,
    required this.type,
    required this.config,
    required this.builder,
  });

  /// The card type, so the bindable list comes from the registry rather than
  /// being repeated at every call site — one source of truth with the
  /// descriptor the inspector builds its panel from.
  final String type;

  final Map<String, dynamic> config;
  final Widget Function(Map<String, dynamic> resolved) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bindable = WidgetRegistry.lookup(type)?.bindable ?? const [];
    if (bindable.isEmpty) return builder(config);

    final bindings = Bindings.fromConfig(config);
    if (bindings.all.isEmpty) return builder(config);

    // Watched only when something is actually bound. An element nobody wired
    // must not rebuild on every device change in the house.
    final devices = ref.watch(devicesProvider).value;
    DeviceState? lookup(String id) =>
        devices?.where((d) => d.id == id).cast<DeviceState?>().firstOrNull;

    return builder(bindings.apply(
      config,
      [
        for (final p in bindable)
          (name: p.name, asText: p.kind == BindKind.text),
      ],
      lookup,
    ));
  }
}
