import '../models/skin_document.dart';
import 'homecore_client.dart';

/// `/skins` — user-defined skins, stored by core as seeds.
///
/// The built-in four are not here: they are compiled into this app and are the
/// floor a data skin layers on top of.
class SkinsApi {
  SkinsApi(this.client);

  final HomecoreClient client;

  Future<List<SkinDocument>> listSkins() async {
    final response = await client.dio.get('/skins');
    final items = (response.data as List? ?? const []);
    return items
        .whereType<Map>()
        .map((m) => SkinDocument.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<SkinDocument> createSkin(SkinDocument skin) async {
    final response = await client.dio.post('/skins', data: skin.toJson());
    return SkinDocument.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }

  Future<SkinDocument> updateSkin(SkinDocument skin) async {
    final response =
        await client.dio.put('/skins/${skin.id}', data: skin.toJson());
    return SkinDocument.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }

  Future<void> deleteSkin(String id) async {
    await client.dio.delete('/skins/$id');
  }
}
