import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/homecore_client.dart';
import '../api/auth_api.dart';

final homecoreClientProvider = Provider<HomecoreClient>((ref) {
  return HomecoreClient();
});

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(homecoreClientProvider));
});

class AuthNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    return ref.read(homecoreClientProvider).hasToken();
  }

  Future<void> login(String username, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authApiProvider).login(username, password);
      return true;
    });
  }

  Future<void> logout() async {
    await ref.read(authApiProvider).logout();
    state = const AsyncData(false);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, bool>(
  AuthNotifier.new,
);
