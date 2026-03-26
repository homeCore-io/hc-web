import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/homecore_client.dart';
import '../api/auth_api.dart';
import '../api/users_api.dart';

final homecoreClientProvider = Provider<HomecoreClient>((ref) {
  return HomecoreClient();
});

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(homecoreClientProvider));
});

final usersApiProvider = Provider<UsersApi>((ref) {
  return UsersApi(ref.watch(homecoreClientProvider));
});

class AuthNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final client = ref.read(homecoreClientProvider);

    // Clear any stale callback from a previous build cycle.
    client.onUnauthorized = null;

    final hasToken = await client.hasToken();
    if (!hasToken) return false;

    // Validate the stored token against the server. If it's expired or invalid,
    // clear it and fall through to the login page.
    try {
      await ref.read(usersApiProvider).me();
    } catch (_) {
      await client.clearToken();
      return false;
    }

    // Token is valid — wire the mid-session 401 callback now so any future
    // expiry during the session triggers an immediate logout/redirect.
    client.onUnauthorized = () {
      state = const AsyncData(false);
    };

    return true;
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

/// Current signed-in user profile. Null if not logged in or fetch fails.
final currentUserProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final isLoggedIn = await ref.watch(authProvider.future);
  if (!isLoggedIn) return null;
  try {
    return await ref.read(usersApiProvider).me();
  } catch (_) {
    return null;
  }
});
