import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/system_health_provider.dart';
import '../../core/text/humanize.dart';
import '../../core/providers/time_display_provider.dart';
import '../../design/components/hc_surface.dart';
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
        Builder(builder: (context) {
          final tk = HcTokens.of(context);
          return IconButton(
            icon: Icon(Icons.refresh, color: tk.surface.onBaseMuted),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(systemHealthProvider);
              ref.invalidate(systemStatusProvider);
            },
          );
        }),
      ],
      child: ListView(
        padding: EdgeInsets.all(t.space.lg),
        children: [
          // ── health + key status as stat tiles ──
          LayoutBuilder(builder: (context, c) {
            final health = healthAsync.valueOrNull;
            final status = statusAsync.valueOrNull;
            final okStatus = health?['status'] as String? ?? 'unknown';
            final ok = okStatus == 'ok';
            final version =
                (status?['version'] ?? health?['version']) as String? ?? '—';
            final uptime = _fmtUptime(status?['uptime_secs'] as int? ?? 0);

            return Wrap(
              spacing: t.space.md,
              runSpacing: t.space.md,
              children: [
                _StatTile(
                  label: 'Status',
                  value: healthAsync.hasError
                      ? 'Unreachable'
                      : (ok ? 'Healthy' : okStatus),
                  accent: healthAsync.hasError
                      ? t.accent.danger
                      : (ok ? t.accent.active : t.accent.warn),
                  dot: true,
                ),
                _StatTile(label: 'Uptime', value: uptime),
                _StatTile(label: 'Version', value: version),
              ],
            );
          }),
          SizedBox(height: t.space.lg),

          // ── detailed status ──
          const SectionLabel('Runtime'),
          statusAsync.when(
            loading: () => const _Loading(),
            error: (e, _) => _ErrorSurface('Status unavailable', '$e'),
            data: (status) {
              final rows = <(IconData, String, String)>[
                (
                  Icons.rule_outlined,
                  'Rules',
                  '${status['rule_count'] as int? ?? 0}'
                ),
                (
                  Icons.device_hub,
                  'Devices',
                  '${status['device_count'] as int? ?? 0}'
                ),
                (
                  Icons.extension_outlined,
                  'Plugins',
                  '${status['plugin_count'] as int? ?? 0}'
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
              ];
              return _RowsSurface([
                for (final r in rows)
                  _KvRow(icon: r.$1, label: r.$2, value: r.$3),
              ]);
            },
          ),
          SizedBox(height: t.space.lg),

          // ── what this house is actually running ──
          const SectionLabel('Versions'),
          ref.watch(systemVersionsProvider).when(
                loading: () => const _Loading(),
                error: (e, _) => _ErrorSurface('Versions unavailable', '$e'),
                data: (versions) {
                  // Whatever core reports, in the order it reports it. A
                  // container image writes a bill of materials here — core, the
                  // SDK, every plugin baked in; a plain binary reports only
                  // itself, and rendering that as one row is the truth rather
                  // than a gap.
                  final entries = versions.entries.toList();
                  if (entries.isEmpty) {
                    return const _ErrorSurface(
                        'No versions reported', 'core returned an empty set');
                  }
                  return _RowsSurface([
                    for (final e in entries)
                      _KvRow(
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
          _RowsSurface([
            _KvRow(
              icon: Icons.account_circle_outlined,
              label: currentUser?['username'] as String? ?? '—',
              value: _displayRole(currentUser?['role'] as String? ?? ''),
            ),
          ]),
          SizedBox(height: t.space.lg),

          // ── display preference ──
          const SectionLabel('Display'),
          HcSurface(
            padding: EdgeInsets.symmetric(
                horizontal: t.space.md, vertical: t.space.xs),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.access_time_outlined,
                  color: t.surface.onBaseMuted),
              title: Text('Show times in UTC',
                  style: TextStyle(color: t.surface.onBase)),
              subtitle: Text(
                isUtc ? 'Timestamps shown as UTC (Z)' : 'Local time',
                style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12.5),
              ),
              activeThumbColor: t.accent.active,
              value: isUtc,
              onChanged: (_) => ref.read(timeUtcProvider.notifier).toggle(),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtUptime(int secs) {
    if (secs <= 0) return '—';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    if (h >= 24) return '${h ~/ 24}d ${h % 24}h';
    if (h >= 1) return '${h}h ${m}m';
    return '${m}m ${secs % 60}s';
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
        'observer' => 'Observer',
        'device_operator' => 'Device Operator',
        'rule_editor' => 'Rule Editor',
        'service_operator' => 'Service Operator',
        _ => role,
      };
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.accent,
    this.dot = false,
  });
  final String label;
  final String value;
  final Color? accent;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return HcSurface(
      padding:
          EdgeInsets.fromLTRB(t.space.md, t.space.md, t.space.md, t.space.md),
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: t.surface.onBaseMuted)),
            SizedBox(height: t.space.sm),
            Row(children: [
              if (dot && accent != null) ...[
                Container(
                  width: 9,
                  height: 9,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: accent ?? t.surface.onBase,
                        fontFeatures: t.numericFontFeatures)),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _RowsSurface extends StatelessWidget {
  const _RowsSurface(this.rows);
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return HcSurface(
      padding: EdgeInsets.symmetric(horizontal: t.space.md),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, color: t.stroke.hairline),
          rows[i],
        ],
      ]),
    );
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.md),
      child: Row(children: [
        Icon(icon, size: 18, color: t.surface.onBaseMuted),
        SizedBox(width: t.space.md),
        Expanded(child: Text(label, style: TextStyle(color: t.surface.onBase))),
        Text(value,
            style: TextStyle(
                color: t.surface.onBaseMuted,
                fontFeatures: t.numericFontFeatures)),
      ]),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return HcSurface(
      padding: EdgeInsets.all(t.space.lg),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorSurface extends StatelessWidget {
  const _ErrorSurface(this.title, this.detail);
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return HcSurface(
      padding: EdgeInsets.all(t.space.md),
      child: Row(children: [
        Icon(Icons.error_outline, color: t.accent.danger, size: 18),
        SizedBox(width: t.space.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: t.surface.onBase)),
              Text(detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12)),
            ],
          ),
        ),
      ]),
    );
  }
}
