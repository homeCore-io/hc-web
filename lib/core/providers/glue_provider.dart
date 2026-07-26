import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/glue_api.dart';
import '../models/device_state.dart';
import 'auth_provider.dart';

final glueApiProvider = Provider<GlueApi>((ref) {
  return GlueApi(ref.watch(homecoreClientProvider));
});

/// The hub's own helper devices.
///
/// `/glue` returns device records, the same shape `/devices` does, so they
/// parse as [DeviceState] and carry their live attributes with them — a
/// timer's remaining seconds are already in here.
final glueProvider = FutureProvider<List<DeviceState>>((ref) async {
  final raw = await ref.watch(glueApiProvider).list();
  final devices = raw.map(DeviceState.fromJson).toList();
  devices.sort((a, b) {
    final byType = (a.deviceType ?? '').compareTo(b.deviceType ?? '');
    return byType != 0 ? byType : a.displayName.compareTo(b.displayName);
  });
  return devices;
});
