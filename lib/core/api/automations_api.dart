import 'homecore_client.dart';
import '../models/rule.dart';

class AutomationsApi {
  final HomecoreClient client;
  AutomationsApi(this.client);

  Future<List<HcRule>> listRules() async {
    final response = await client.dio.get('/automations');
    return (response.data as List)
        .map((e) => HcRule.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<HcRule> createRule(Map<String, dynamic> json) async {
    final response = await client.dio.post('/automations', data: json);
    return HcRule.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<HcRule> updateRule(String id, Map<String, dynamic> json) async {
    final response = await client.dio.put('/automations/$id', data: json);
    return HcRule.fromJson(Map<String, dynamic>.from(response.data as Map));
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
}
