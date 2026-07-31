import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/automations_provider.dart';
import '../../core/providers/scenes_provider.dart';
import '../../core/providers/system_config_provider.dart';
import '../../core/web/browser_files.dart';
import '../../design/components/hc_surface.dart';
import '../../core/providers/system_health_provider.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';

/// Backups, restores, and the calendars the house reads.
///
/// Grouped because they are the same kind of thing — data going in and out of
/// core, rather than settings that change how it behaves.
class DataPage extends ConsumerStatefulWidget {
  const DataPage({super.key});

  @override
  ConsumerState<DataPage> createState() => _DataPageState();
}

class _DataPageState extends ConsumerState<DataPage> {
  bool _working = false;
  String? _status;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final calendars = ref.watch(calendarsProvider);

    return SectionScaffold(
      title: 'Data',
      subtitle: 'Backups and calendars',
      child: ListView(
        padding: EdgeInsets.all(t.space.lg),
        children: [
          if (_status != null) ...[
            _Note(_status!),
            SizedBox(height: t.space.md),
          ],
          const SectionLabel('Backup'),
          _Card(
            title: 'Download a backup',
            body: 'Both databases, homecore.toml, modes and every rule, as one '
                'zip. The history database is nearly all of the size.'
                '${_lastBackupSentence(ref)}',
            action: FilledButton(
              onPressed: _working ? null : _backup,
              child: Text(_working ? 'Working…' : 'Download'),
            ),
          ),
          SizedBox(height: t.space.sm),
          _Card(
            title: 'Restore from a backup',
            body: 'Replaces the devices, rules, scenes, areas, users and '
                'configuration in this house with the contents of the file. '
                'Core needs a restart afterwards to run on them.',
            danger: true,
            action: OutlinedButton(
              onPressed: _working ? null : _restore,
              child: const Text('Choose file…'),
            ),
          ),
          SizedBox(height: t.space.lg),
          const SectionLabel('Automations & scenes'),
          Padding(
            padding: EdgeInsets.only(bottom: t.space.sm),
            child: Text(
              'The half of a backup worth moving on its own. A whole-house '
              'archive is mostly history and restoring one replaces '
              'everything; these are just the rules and scenes, as JSON.',
              style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted),
            ),
          ),
          _Card(
            title: 'Export automations',
            body: 'Every rule as core holds it. Keep it, diff it, or load it '
                'into another house.',
            action: OutlinedButton(
              onPressed: _working ? null : () => _export(scenes: false),
              child: const Text('Export'),
            ),
          ),
          SizedBox(height: t.space.sm),
          _Card(
            title: 'Import automations',
            body: 'Adds the rules in the file — it does not replace what is '
                'here. Core gives each one a new id, so importing this '
                "house's own export leaves you with two of everything. A rule "
                'naming a device that does not exist is refused.',
            action: OutlinedButton(
              onPressed: _working ? null : () => _import(scenes: false),
              child: const Text('Choose file…'),
            ),
          ),
          SizedBox(height: t.space.sm),
          _Card(
            title: 'Export scenes',
            body: 'Every scene and the device states it sets.',
            action: OutlinedButton(
              onPressed: _working ? null : () => _export(scenes: true),
              child: const Text('Export'),
            ),
          ),
          SizedBox(height: t.space.sm),
          _Card(
            title: 'Import scenes',
            body: 'Adds, like automations — new ids, nothing replaced.',
            action: OutlinedButton(
              onPressed: _working ? null : () => _import(scenes: true),
              child: const Text('Choose file…'),
            ),
          ),
          SizedBox(height: t.space.lg),
          Row(
            children: [
              const Expanded(child: SectionLabel('Calendars')),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add calendar'),
                onPressed: _working ? null : _addCalendar,
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(bottom: t.space.sm),
            child: Text(
              'An automation can trigger on a calendar event. Core fetches the '
              'feed and expands recurring events itself.',
              style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted),
            ),
          ),
          calendars.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _Note('Calendars unavailable: $e'),
            data: (list) => list.isEmpty
                ? const _Note(
                    'No calendars. Add one by URL — an .ics or webcal feed.')
                : Column(
                    children: [
                      for (final c in list)
                        _CalendarRow(
                          calendar: c,
                          onDelete: () => _deleteCalendar('${c['id']}'),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Appended to the download card so the answer to "do I need to?" is on the
  /// button that does it.
  ///
  /// Core derives this from the audit log, which is pruned, so silence means
  /// "nothing on record" rather than "never" — and an empty string is better
  /// than a sentence asserting either.
  String _lastBackupSentence(WidgetRef ref) {
    final status = ref.watch(systemStatusProvider).valueOrNull;
    if (status == null) return '';
    final raw = status['last_backup_at'];
    if (raw is! String) return ' No backup on record for this house.';
    final at = DateTime.tryParse(raw)?.toLocal();
    if (at == null) return '';
    final days = DateTime.now().difference(at).inDays;
    if (days == 0) return ' Last backed up today.';
    return ' Last backed up $days day${days == 1 ? '' : 's'} ago.';
  }

  /// Hand over rules or scenes as JSON.
  ///
  /// Named for the day it is opened, because the first question of a file
  /// found in a downloads folder a year later is when it came from.
  Future<void> _export({required bool scenes}) async {
    final what = scenes ? 'scenes' : 'automations';
    setState(() {
      _working = true;
      _status = null;
    });
    try {
      final api = ref.read(systemDataApiProvider);
      final data =
          scenes ? await api.exportScenes() : await api.exportAutomations();
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      final stamp = DateTime.now().toIso8601String().split('T').first;
      downloadBytes(
        Uint8List.fromList(utf8.encode(pretty)),
        'homecore-$what-$stamp.json',
        mime: 'application/json',
      );
      if (mounted) {
        setState(() => _status = 'Exported ${data.length} $what.');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _import({required bool scenes}) async {
    final what = scenes ? 'scenes' : 'automations';
    final file = await pickFile(accept: '.json,application/json');
    if (file == null) return;
    setState(() {
      _working = true;
      _status = null;
    });
    try {
      final decoded = jsonDecode(utf8.decode(file.bytes));
      if (decoded is! List) {
        setState(() {
          _status = 'That file is not an export: expected a JSON array '
              'of $what.';
        });
        return;
      }
      final api = ref.read(systemDataApiProvider);
      final res = scenes
          ? await api.importScenes(decoded)
          : await api.importAutomations(decoded);
      if (!mounted) return;
      setState(() => _status = res.ok
          ? 'Added ${res.imported} $what from ${file.name}. Nothing was replaced.'
          : 'Import failed: ${res.detail}');
      if (res.ok) {
        // Invalidated separately: the two providers are different types, and a
        // ternary between them widens to Object, which invalidate refuses.
        if (scenes) {
          ref.invalidate(scenesProvider);
        } else {
          ref.invalidate(automationsProvider);
        }
      }
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _status = 'That file is not JSON: ${e.message}');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _backup() async {
    setState(() {
      _working = true;
      _status = 'Building the archive — this takes a while on a large history.';
    });
    try {
      final (name, bytes) = await ref.read(systemDataApiProvider).backup();
      downloadBytes(bytes, name, mime: 'application/zip');
      if (mounted) {
        setState(() => _status = 'Downloaded $name (${_mb(bytes.length)}).');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Backup failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restore() async {
    final file = await pickFile(accept: '.zip,application/zip');
    if (file == null || !mounted) return;

    // Confirm against the file the operator actually chose — name and size —
    // because this is the one action here that cannot be undone.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore this house?'),
        content: Text(
          'Restoring from ${file.name} (${_mb(file.bytes.length)}) replaces '
          'the devices, rules, scenes, areas, users and configuration that are '
          'here now. There is no undo — take a backup first if you have not.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _working = true;
      _status = 'Restoring…';
    });
    try {
      final summary = await ref.read(systemDataApiProvider).restore(file.bytes);
      if (mounted) {
        setState(() => _status =
            'Restored. Restart core to run on it. Core said: $summary');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Restore failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _addCalendar() async {
    final urlCtl = TextEditingController();
    final nameCtl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a calendar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlCtl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Feed URL',
                hintText: 'https://… .ics  or  webcal://…',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                helperText: 'What rules will call it.',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Fetch')),
        ],
      ),
    );
    if (ok != true || urlCtl.text.trim().isEmpty) return;

    setState(() => _working = true);
    try {
      await ref.read(systemDataApiProvider).addCalendar(
            url: urlCtl.text.trim(),
            name: nameCtl.text.trim(),
          );
      ref.invalidate(calendarsProvider);
      if (mounted) setState(() => _status = 'Calendar fetched.');
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not fetch it: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _deleteCalendar(String id) async {
    try {
      await ref.read(systemDataApiProvider).deleteCalendar(id);
      ref.invalidate(calendarsProvider);
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not remove it: $e');
    }
  }

  static String _mb(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(0)} KB';
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.body,
    required this.action,
    this.danger = false,
  });

  final String title;
  final String body;
  final Widget action;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return HcSurface(
      padding: EdgeInsets.all(t.space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: danger ? t.accent.danger : t.surface.onBase,
                    )),
                const SizedBox(height: 4),
                Text(body,
                    style: TextStyle(
                        fontSize: 12.5, color: t.surface.onBaseMuted)),
              ],
            ),
          ),
          SizedBox(width: t.space.md),
          action,
        ],
      ),
    );
  }
}

class _CalendarRow extends StatelessWidget {
  const _CalendarRow({required this.calendar, required this.onDelete});

  final Map<String, dynamic> calendar;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final upcoming = calendar['upcoming_count'] ?? 0;
    final total = calendar['event_count'] ?? 0;

    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: HcSurface(
        padding:
            EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
        child: Row(
          children: [
            Icon(Icons.event_outlined, size: 18, color: t.surface.onBaseMuted),
            SizedBox(width: t.space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${calendar['id']}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '$upcoming upcoming · $total events'
                    '${calendar['source_url'] != null ? ' · fetched from a URL' : ''}',
                    style:
                        TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted),
                  ),
                ],
              ),
            ),
            IconButton(
              icon:
                  Icon(Icons.delete_outline, size: 18, color: t.accent.danger),
              tooltip: 'Remove',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
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
