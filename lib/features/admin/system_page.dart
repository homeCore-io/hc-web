import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/system_health_provider.dart';
import '../../core/text/humanize.dart';
import '../../core/providers/time_display_provider.dart';
import '../../design/components/hc_controls.dart';
import '../../design/components/hc_rows.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';

// Both live in core/providers now: Administration's header shows the same
// health above every section, and two private copies meant two requests for
// one answer.
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
      ref.invalidate(systemStatusProvider);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final healthAsync = ref.watch(systemHealthProvider);
    final statusAsync = ref.watch(systemStatusProvider);
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final isUtc = ref.watch(timeUtcProvider);

    // Headline health, mirroring the Status stat tile in the body.
    final healthStatus = healthAsync.valueOrNull?['status'] as String? ?? '';
    final healthy = healthStatus == 'ok';
    final SectionStat? statusStat = healthAsync.hasError
        ? const SectionStat(
            value: 'Unreachable', label: '', tone: SectionTone.danger)
        : healthAsync.hasValue
            ? SectionStat(
                value: healthy ? 'Healthy' : healthStatus,
                label: '',
                tone: healthy ? SectionTone.active : SectionTone.warn,
                glow: healthy)
            : null;

    return SectionScaffold(
      title: 'System',
      stats: [if (statusStat != null) statusStat],
      actions: [
        HcIconButton(
          icon: Icons.refresh,
          tooltip: 'Refresh',
          onPressed: () {
            ref.invalidate(systemHealthProvider);
            ref.invalidate(systemStatusProvider);
          },
        ),
      ],
      child: ListView(
        padding: EdgeInsets.all(t.space.lg),
        children: [
          // No status/uptime/version tiles here.
          //
          // The shell header above this pane already says "Healthy · core
          // 0.1.6 · 18h 48m uptime". Repeating it as three large tiles was
          // both duplication and the reason this section looked unlike every
          // other one in Administration, which are rows and cards. The same
          // facts are rows below, where the rest of the runtime already lives.

          // ── detailed status ──
          const SectionLabel('Runtime'),
          statusAsync.when(
            loading: () => const HcRowsLoading(rows: 7),
            error: (e, _) =>
                HcRowsNotice.error(title: 'Status unavailable', detail: '$e'),
            data: (status) {
              final rows = <(IconData, String, String)>[
                (Icons.rule_outlined, 'Rules', _count(status['rules_total'])),
                (Icons.device_hub, 'Devices', _count(status['devices_total'])),
                (
                  Icons.extension_outlined,
                  'Plugins',
                  _count(status['plugins_active'])
                ),
                (
                  Icons.storage_outlined,
                  'State DB',
                  _fmtBytes(status['state_db_bytes'] as int? ?? 0)
                ),
                (
                  Icons.history,
                  'History DB',
                  _fmtBytes(status['history_db_bytes'] as int? ?? 0)
                ),
                (
                  Icons.timer_outlined,
                  'Uptime',
                  status['uptime_seconds'] is num
                      ? formatUptime(status['uptime_seconds'] as num)
                      : '—'
                ),
                (Icons.schedule, 'Timezone', '${status['timezone'] ?? '—'}'),
              ];
              return HcRows([
                for (final r in rows)
                  HcKvRow(icon: r.$1, label: r.$2, value: r.$3),
              ]);
            },
          ),
          SizedBox(height: t.space.lg),

          // ── what this house is actually running ──
          const SectionLabel('Versions'),
          ref.watch(systemVersionsProvider).when(
                loading: () => const HcRowsLoading(rows: 2),
                error: (e, _) => HcRowsNotice.error(
                    title: 'Versions unavailable', detail: '$e'),
                data: (versions) {
                  // Whatever core reports, in the order it reports it. A
                  // container image writes a bill of materials here — core, the
                  // SDK, every plugin baked in; a plain binary reports only
                  // itself, and rendering that as one row is the truth rather
                  // than a gap.
                  final entries = versions.entries.toList();
                  if (entries.isEmpty) {
                    return const HcRowsNotice(
                      title: 'No versions reported',
                      detail: 'core returned an empty set',
                    );
                  }
                  return HcRows([
                    for (final e in entries)
                      HcKvRow(
                        icon: Icons.inventory_2_outlined,
                        label: humanize(e.key),
                        value: '${e.value}',
                      ),
                  ]);
                },
              ),
          SizedBox(height: t.space.lg),

          // ── this session ──
          const SectionLabel('Signed in as'),
          HcRows([
            HcKvRow(
              icon: Icons.account_circle_outlined,
              label: currentUser?['username'] as String? ?? '—',
              value: _displayRole(currentUser?['role'] as String? ?? ''),
            ),
          ]),
          SizedBox(height: t.space.lg),

          // ── display preference ──
          const SectionLabel('Display'),
          HcRows([
            HcToggleRow(
              icon: Icons.access_time_outlined,
              label: 'Show times in UTC',
              subtitle: isUtc ? 'Timestamps shown as UTC (Z)' : 'Local time',
              value: isUtc,
              onChanged: (_) => ref.read(timeUtcProvider.notifier).toggle(),
            ),
          ]),
        ],
      ),
    );
  }

  /// A count, or an em dash when core did not send one.
  ///
  /// This used to be `status['rule_count'] as int? ?? 0`, against keys core
  /// does not send — it sends rules_total, devices_total, plugins_active. The
  /// `?? 0` turned every one of those misses into a confident zero, so a house
  /// with 34 rules and 190 devices reported none of them, and only the two
  /// keys that happened to match (the database sizes) were ever right. A
  /// missing key is now visibly missing.
  static String _count(Object? v) => v is num ? '$v' : '—';

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _displayRole(String role) => switch (role) {
        'admin' => 'Admin',
        'user' => 'User',
        'read_only' => 'Read Only',
        'observer' => 'Observer',
        'device_operator' => 'Device Operator',
        'rule_editor' => 'Rule Editor',
        'service_operator' => 'Service Operator',
        _ => role,
      };
}
