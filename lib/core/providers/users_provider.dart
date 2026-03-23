import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_entry.dart';
import 'auth_provider.dart';

class UsersNotifier extends AsyncNotifier<List<UserEntry>> {
  @override
  Future<List<UserEntry>> build() async {
    final raw = await ref.read(usersApiProvider).listUsers();
    return raw.map(UserEntry.fromJson).toList();
  }
}

final usersProvider =
    AsyncNotifierProvider<UsersNotifier, List<UserEntry>>(UsersNotifier.new);
