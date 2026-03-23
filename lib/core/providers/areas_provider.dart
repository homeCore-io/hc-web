import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/areas_api.dart';
import 'auth_provider.dart';

final areasApiProvider = Provider<AreasApi>((ref) {
  return AreasApi(ref.watch(homecoreClientProvider));
});

final areasProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final raw = await ref.read(areasApiProvider).listAreas();
  return raw;
});
