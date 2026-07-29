import 'homecore_client.dart';
import '../rules/rule.dart';

class AutomationsApi {
  final HomecoreClient client;
  AutomationsApi(this.client);

  Future<List<HcRule>> listRules() async {
    final response = await client.dio.get('/automations');
    return (response.data as List)
        .map((e) => HcRule.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Core assigns the UUID on create and overwrites whatever `id` we send.
  Future<HcRule> createRule(HcRule rule) async {
    final response = await client.dio.post('/automations', data: rule.toJson());
    return HcRule.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<HcRule> updateRule(HcRule rule) async {
    final response =
        await client.dio.put('/automations/${rule.id}', data: rule.toJson());
    return HcRule.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  /// The RON source core actually stores. Backs the editor's read-only
  /// "Source" tab, and is the honest answer to "what did I just save?".
  Future<String> getRuleRon(String id) async {
    final response = await client.dio.get('/automations/$id/ron');
    return '${response.data}';
  }

  Future<void> patchRule(String id, Map<String, dynamic> patch) async {
    await client.dio.patch('/automations/$id', data: patch);
  }

  Future<void> deleteRule(String id) async {
    await client.dio.delete('/automations/$id');
  }

  Future<Map<String, dynamic>> testRule(String id) async {
    final response = await client.dio.post('/automations/$id/test');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<HcRule> cloneRule(String id) async {
    final response = await client.dio.post('/automations/$id/clone');
    return HcRule.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<List<Map<String, dynamic>>> getRuleHistory(String id) async {
    final response = await client.dio.get('/automations/$id/history');
    return (response.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> bulkPatch(Map<String, dynamic> patch) async {
    await client.dio.patch('/automations', data: patch);
  }

  Future<List<Map<String, dynamic>>> listGroups() async {
    final response = await client.dio.get('/automations/groups');
    return (response.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createGroup(Map<String, dynamic> body) async {
    final response = await client.dio.post('/automations/groups', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateGroup(
      String id, Map<String, dynamic> body) async {
    final response =
        await client.dio.patch('/automations/groups/$id', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteGroup(String id) async {
    await client.dio.delete('/automations/groups/$id');
  }

  Future<void> setGroupEnabled(String id, {required bool enabled}) async {
    await client.dio
        .post('/automations/groups/$id/${enabled ? 'enable' : 'disable'}');
  }
}
