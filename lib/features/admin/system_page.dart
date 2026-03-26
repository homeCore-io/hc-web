import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/auth_provider.dart';

final _healthProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.read(homecoreClientProvider);
  final response = await client.dio.get('/health');
  return Map<String, dynamic>.from(response.data as Map);
});

class SystemPage extends ConsumerWidget {
  const SystemPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(_healthProvider);
    final currentUser = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('System'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(_healthProvider)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader('Health'),
          healthAsync.when(
            loading: () => const Card(
              child: ListTile(
                leading: CircularProgressIndicator(),
                title: Text('Checking...'),
              ),
            ),
            error: (e, _) => Card(
              child: ListTile(
                leading: Icon(Icons.error_outline,
                    color: Theme.of(context).colorScheme.error),
                title: const Text('Unreachable'),
                subtitle: Text('$e'),
              ),
            ),
            data: (health) {
              final status = health['status'] as String? ?? 'unknown';
              final version = health['version'] as String? ?? '—';
              final ok = status == 'ok';
              return Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        ok ? Icons.check_circle_outline : Icons.warning_amber,
                        color: ok ? Colors.green : Colors.orange,
                      ),
                      title: Text(ok ? 'Healthy' : status),
                      subtitle: Text('Version $version'),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          const _SectionHeader('Signed in as'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(currentUser?['username'] as String? ?? '—'),
              subtitle: Text(
                  _displayRole(currentUser?['role'] as String? ?? '')),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionHeader('API'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.api),
              title: const Text('OpenAPI spec'),
              subtitle: const Text('/api/v1/openapi.json'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () {
                // Opens in same tab — acceptable for an admin tool
                final base = Uri.base;
                final url = Uri(
                  scheme: base.scheme,
                  host: base.host,
                  port: base.port,
                  path: '/api/v1/openapi.json',
                ).toString();
                // ignore: avoid_print
                print('Navigate to $url');
              },
            ),
          ),
        ],
      ),
    );
  }

  String _displayRole(String role) => switch (role) {
        'admin' => 'Admin',
        'user' => 'User',
        'read_only' => 'Read Only',
        _ => role,
      };
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
