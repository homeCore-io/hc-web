import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/system_config_api.dart';
import '../../features/plugins/config_descriptor/descriptor.dart';
import 'auth_provider.dart';

final systemConfigApiProvider = Provider<SystemConfigApi>((ref) {
  return SystemConfigApi(ref.watch(homecoreClientProvider));
});

/// The file and the description of it, fetched together.
///
/// Together because neither is useful alone: values with no descriptor is a
/// JSON dump, and a descriptor with no values is an empty form. One provider
/// also means one loading state, so the screen never renders half of itself.
class SystemConfigBundle {
  const SystemConfigBundle({required this.config, required this.descriptor});
  final SystemConfig config;
  final ConfigDescriptor descriptor;
}

class SystemConfigNotifier extends AsyncNotifier<SystemConfigBundle> {
  @override
  Future<SystemConfigBundle> build() async {
    final api = ref.read(systemConfigApiProvider);
    final config = await api.get();
    final descriptor = ConfigDescriptor.fromJson(await api.descriptor());
    return SystemConfigBundle(config: config, descriptor: descriptor);
  }

  /// Re-read after a save, so the raw view and the parsed view cannot drift
  /// apart — a patch rewrites the file, and the raw text the editor holds is
  /// stale the moment it lands.
  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final systemConfigProvider =
    AsyncNotifierProvider<SystemConfigNotifier, SystemConfigBundle>(
  SystemConfigNotifier.new,
);
