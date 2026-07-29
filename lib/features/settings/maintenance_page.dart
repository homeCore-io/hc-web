import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/device_state.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/components/hc_surface.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';

/// Rules pointing at devices that are gone, and devices no plugin claims.
///
/// Both halves are quiet failures: a rule with a dead reference does nothing
/// every time it fires, and a device nothing owns sits in every picker
/// forever. Neither shows up anywhere else in the app.
final staleRefsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(homecoreClientProvider);
  final res = await client.dio.get('/automations/stale-refs');
  return [
    for (final r in (res.data as List)) Map<String, dynamic>.from(r as Map),
  ];
});

class MaintenancePage extends ConsumerStatefulWidget {
  const MaintenancePage({super.key});

  @override
  ConsumerState<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends ConsumerState<MaintenancePage> {
  final _selected = <String>{};
  bool _busy = false;
  String? _status;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final stale = ref.watch(staleRefsProvider);
    final devices = ref.watch(devicesProvider).valueOrNull ?? const [];
    final orphans = _orphans(devices);

    return SectionScaffold(
      title: 'Maintenance',
      subtitle: 'The things that fail quietly',
      stats: [
        if (stale.hasValue && stale.value!.isNotEmpty)
          SectionStat(
              value: '${stale.value!.length}',
              label: 'broken rules',
              tone: SectionTone.danger),
        if (orphans.isNotEmpty)
          SectionStat(
              value: '${orphans.length}',
              label: 'unclaimed',
              tone: SectionTone.warn),
      ],
      actions: [
        Builder(builder: (context) {
          final tk = HcTokens.of(context);
          return IconButton(
            icon: Icon(Icons.refresh, color: tk.surface.onBaseMuted),
            tooltip: 'Re-check',
            onPressed: () {
              ref.invalidate(staleRefsProvider);
              ref.invalidate(devicesProvider);
            },
          );
        }),
      ],
      child: ListView(
        padding: EdgeInsets.all(t.space.lg),
        children: [
          if (_status != null) ...[
            _Note(_status!),
            SizedBox(height: t.space.md),
          ],
          const SectionLabel('Rules pointing at devices that no longer exist'),
          Padding(
            padding: EdgeInsets.only(bottom: t.space.sm),
            child: Text(
              'These fire and do nothing. Open the rule to point it at the '
              'device that replaced the missing one, or delete it.',
              style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted),
            ),
          ),
          stale.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _Note('Could not check: $e'),
            data: (rows) => rows.isEmpty
                ? const _Clear('Every rule points at a device that exists.')
                : Column(
                    children: [
                      for (final r in rows) _StaleRow(row: r),
                    ],
                  ),
          ),
          SizedBox(height: t.space.lg),
          const SectionLabel('Devices no plugin claims'),
          Padding(
            padding: EdgeInsets.only(bottom: t.space.sm),
            child: Text(
              'Registered once, never seen again — a plugin that was removed, '
              'or hardware that went away. Deleting one nullifies its '
              'references in any rule that mentions it.',
              style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted),
            ),
          ),
          if (orphans.isEmpty)
            const _Clear('Every device has a plugin behind it.')
          else ...[
            for (final d in orphans)
              _OrphanRow(
                device: d,
                selected: _selected.contains(d.id),
                onChanged: (v) => setState(() {
                  if (v) {
                    _selected.add(d.id);
                  } else {
                    _selected.remove(d.id);
                  }
                }),
              ),
            SizedBox(height: t.space.sm),
            Row(
              children: [
                Text('${_selected.length} selected',
                    style: TextStyle(
                        fontSize: 12.5, color: t.surface.onBaseMuted)),
                const Spacer(),
                OutlinedButton(
                  onPressed:
                      _selected.isEmpty || _busy ? null : _deleteSelected,
                  child: Text(_busy ? 'Deleting…' : 'Delete selected'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// A device whose plugin is not running and which has not been seen.
  ///
  /// Deliberately narrow: unavailable alone is a light that is switched off at
  /// the wall, and this list is a delete button. A device only qualifies when
  /// nothing has claimed it — no plugin id the plugin list knows about.
  List<DeviceState> _orphans(List<DeviceState> devices) {
    final livePlugins = {
      for (final d in devices)
        if (d.available) d.pluginId,
    };
    return [
      for (final d in devices)
        if (!d.available && !livePlugins.contains(d.pluginId)) d,
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            Text('Delete ${ids.length} device${ids.length == 1 ? '' : 's'}?'),
        content: Text(
          'Any rule that mentions ${ids.length == 1 ? 'it' : 'them'} keeps '
          'working, with the reference nullified — which usually means the '
          'rule stops doing what it was written to do. Check the list above '
          'afterwards.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final client = ref.read(homecoreClientProvider);
      final res = await client.dio.delete('/devices', data: {'ids': ids});
      final body = Map<String, dynamic>.from(res.data as Map);
      ref.invalidate(devicesProvider);
      ref.invalidate(staleRefsProvider);
      if (mounted) {
        setState(() {
          _selected.clear();
          _status = 'Deleted ${body['deleted'] ?? ids.length}. '
              'Rules affected: ${(body['affected_rules'] as List?)?.length ?? 0}.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Delete failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _StaleRow extends StatelessWidget {
  const _StaleRow({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final ids = (row['stale_device_ids'] as List?) ?? const [];

    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: HcSurface(
        padding:
            EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
        child: Row(
          children: [
            Icon(Icons.link_off, size: 18, color: t.accent.danger),
            SizedBox(width: t.space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${row['rule_name'] ?? row['rule_id']}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    ids.join(', '),
                    style: TextStyle(
                      fontSize: 12,
                      color: t.surface.onBaseMuted,
                      fontFeatures: t.numericFontFeatures,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => context.push('/automations/${row['rule_id']}'),
              child: const Text('Open rule'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrphanRow extends StatelessWidget {
  const _OrphanRow({
    required this.device,
    required this.selected,
    required this.onChanged,
  });

  final DeviceState device;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: HcSurface(
        padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              onChanged: (v) => onChanged(v ?? false),
            ),
            Expanded(
              child: Text(device.displayName,
                  style: const TextStyle(fontSize: 13.5)),
            ),
            Text(device.id,
                style: TextStyle(
                    fontSize: 12,
                    color: t.surface.onBaseMuted,
                    fontFeatures: t.numericFontFeatures)),
            SizedBox(width: t.space.md),
            SizedBox(
              width: 150,
              child: Text(device.pluginId,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: t.surface.onBaseMuted)),
            ),
            SizedBox(width: t.space.sm),
          ],
        ),
      ),
    );
  }
}

class _Clear extends StatelessWidget {
  const _Clear(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Row(
      children: [
        Icon(Icons.check_circle_outline, size: 16, color: t.accent.success),
        SizedBox(width: t.space.sm),
        Text(text,
            style: TextStyle(fontSize: 13, color: t.surface.onBaseMuted)),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
      decoration: BoxDecoration(
        color: t.surface.raised,
        border: Border.all(color: t.stroke.hairline),
        borderRadius: BorderRadius.circular(t.radius.md),
      ),
      child: SelectableText(text,
          style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted)),
    );
  }
}
