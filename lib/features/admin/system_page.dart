import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/time_display_provider.dart';

final _healthProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.read(homecoreClientProvider);
  final response = await client.dio.get('/health');
  return Map<String, dynamic>.from(response.data as Map);
});

final _statusProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.read(homecoreClientProvider);
  final response = await client.dio.get('/system/status');
  return Map<String, dynamic>.from(response.data as Map);
});

class SystemPage extends ConsumerStatefulWidget {
  const SystemPage({super.key});

  @override
  ConsumerState<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends ConsumerState<SystemPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(_statusProvider);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final healthAsync = ref.watch(_healthProvider);
    final statusAsync = ref.watch(_statusProvider);
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final isUtc = ref.watch(timeUtcProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('System'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.invalidate(_healthProvider);
                ref.invalidate(_statusProvider);
              }),
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
          const _SectionHeader('Status'),
          statusAsync.when(
            loading: () => const Card(
              child: ListTile(
                leading: CircularProgressIndicator(),
                title: Text('Loading...'),
              ),
            ),
            error: (e, _) => Card(
              child: ListTile(
                leading: Icon(Icons.error_outline,
                    color: Theme.of(context).colorScheme.error),
                title: const Text('Status unavailable'),
                subtitle: Text('$e'),
              ),
            ),
            data: (status) {
              final uptimeSecs = status['uptime_secs'] as int? ?? 0;
              final version = status['version'] as String? ?? '—';
              final ruleCount = status['rule_count'] as int? ?? 0;
              final deviceCount = status['device_count'] as int? ?? 0;
              final pluginCount = status['plugin_count'] as int? ?? 0;
              final stateDbBytes = status['state_db_bytes'] as int? ?? 0;
              final historyDbBytes = status['history_db_bytes'] as int? ?? 0;

              return Card(
                child: Column(
                  children: [
                    _StatusRow(Icons.timer_outlined, 'Uptime', _fmtUptime(uptimeSecs)),
                    _StatusRow(Icons.info_outline, 'Version', version),
                    _StatusRow(Icons.rule_outlined, 'Rules', '$ruleCount'),
                    _StatusRow(Icons.device_hub, 'Devices', '$deviceCount'),
                    _StatusRow(Icons.extension_outlined, 'Plugins', '$pluginCount'),
                    _StatusRow(Icons.storage_outlined, 'State DB', _fmtBytes(stateDbBytes)),
                    _StatusRow(Icons.history, 'History DB', _fmtBytes(historyDbBytes)),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          const _SectionHeader('Display'),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.access_time_outlined),
              title: const Text('Show times in UTC'),
              subtitle: Text(isUtc ? 'Timestamps shown as UTC (Z)' : 'Timestamps shown in local time'),
              value: isUtc,
              onChanged: (_) => ref.read(timeUtcProvider.notifier).toggle(),
            ),
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

  String _fmtUptime(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    return '${h}h ${m}m ${s}s';
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _displayRole(String role) => switch (role) {
        'admin' => 'Admin',
        'user' => 'User',
        'read_only' => 'Read Only',
        _ => role,
      };
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatusRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: Icon(icon, size: 20),
        title: Text(label),
        trailing: Text(value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary)),
      );
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
