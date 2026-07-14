import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rules/vocabulary.dart';
import 'auth_provider.dart';

/// Asks the core in front of us what a rule may contain, and compares that with
/// what this app believes.
///
/// The build-time check (`vocabulary_test.dart`) compares against a COMMITTED
/// fixture, which only helps if somebody ran `tool/sync-vocabulary.sh`. Nobody
/// will always remember, and a user pointing this app at a newer core would
/// otherwise just find that some of their rules render as "Unsupported" with no
/// explanation at all.
///
/// **A core without the endpoint is not an error.** `GET /automations/vocabulary`
/// is new; every core older than it 404s, and hitting one simply means we cannot
/// check — so the result is null and nothing is said. Turning "I could not ask"
/// into a red banner would be its own kind of lie, and it would fire on every
/// deployment that has not been upgraded yet.
final vocabularyProvider = FutureProvider<Vocabulary?>((ref) async {
  final client = ref.watch(homecoreClientProvider);

  try {
    final response = await client.dio.get('/automations/vocabulary');
    return Vocabulary.fromJson(Map<String, dynamic>.from(response.data as Map));
  } on DioException catch (_) {
    // ANY failure means "could not ask", and it is deliberately not narrowed to
    // a 404.
    //
    // An older core does not answer 404 here — it answers **400**. There is no
    // `/automations/vocabulary` route, so the path falls through to
    // `/automations/:id`, which tries to parse "vocabulary" as a Uuid and fails.
    // Checking for a 404 would therefore have missed the exact case this whole
    // fallback exists for. (Verified against a live older core, and pinned in
    // core by `the_vocabulary_route_is_not_shadowed_by_the_id_route`.)
    //
    // A network failure or a 500 is also not worth shouting about from here: if
    // core is unreachable the rest of the app is already saying so loudly, and a
    // vocabulary check is not where anyone should find that out.
    return null;
  } catch (_) {
    return null;
  }
});

/// What this app cannot express about the core it is talking to.
///
/// Null when we could not ask (an older core). Empty when we asked and agree.
final vocabularyDriftProvider = Provider<VocabularyDrift?>((ref) {
  final vocab = ref.watch(vocabularyProvider).valueOrNull;
  if (vocab == null) return null;
  return VocabularyDrift.between(vocab);
});
