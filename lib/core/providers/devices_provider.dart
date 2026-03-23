import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/devices_api.dart';
import '../models/device_state.dart';
import 'auth_provider.dart';

final devicesApiProvider = Provider<DevicesApi>((ref) {
  return DevicesApi(ref.watch(homecoreClientProvider));
});

final devicesProvider = FutureProvider<List<DeviceState>>((ref) async {
  final api = ref.watch(devicesApiProvider);
  final raw = await api.listDevices();
  return raw.map(DeviceState.fromJson).toList();
});
