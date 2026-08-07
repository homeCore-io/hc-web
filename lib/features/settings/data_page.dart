import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/automations_provider.dart';
import '../../core/providers/scenes_provider.dart';
import '../../core/providers/system_config_provider.dart';
import '../../core/web/browser_files.dart';
import '../../design/components/hc_controls.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/components/hc_rows.dart';
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

  /// Every failure path writes "`<verb>` failed: …"; nothing else does.
  bool get _failed => _status?.contains('failed') ?? false;

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
            HcRowsNotice(
              title: _status!,
              icon: _failed ? Icons.error_outline : Icons.check_circle_outline,
              danger: _failed,
            ),
            SizedBox(height: t.space.md),
          ],
          const SectionLabel('Backup'),
          HcRows([
            HcRow(
              icon: Icons.archive_outlined,
              label: 'Download a backup',
              subtitle:
                  'Both databases, homecore.toml, modes and every rule, as one '
                  'zip. The history database is nearly all of the size.'
                  '${_lastBackupSentence(ref)}',
              trailing: HcButton(
                label: _working ? 'Working…' : 'Download',
                kind: HcButtonKind.primary,
                onPressed: _working ? null : _backup,
              ),
            ),
            HcRow(
              icon: Icons.settings_backup_restore,
              label: 'Restore from a backup',
              subtitle: 'Replaces the devices, rules, scenes, areas, users and '
                  'configuration in this house with the contents of the file. '
                  'Core needs a restart afterwards to run on them.',
              danger: true,
              trailing: HcButton(
                label: 'Choose file…',
                kind: HcButtonKind.danger,
                onPressed: _working ? null : _restore,
              ),
            ),
          ]),
          SizedBox(height: t.space.lg),
          const SectionLabel('Automations & scenes'),
          Padding(
            padding: EdgeInsets.only(bottom: t.space.sm),
            child: Text(
              'The half of a backup worth moving on its own. A whole-house '
              'archive is mostly history and restoring one replaces '
              'everything; these are just the rules and scenes, as JSON.',
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted),
            ),
          ),
          HcRows([
            HcRow(
              icon: Icons.rule_outlined,
              label: 'Export automations',
              subtitle: 'Every rule as core holds it. Keep it, diff it, or '
                  'load it into another house.',
              trailing: HcButton(
                label: 'Export',
                kind: HcButtonKind.ghost,
                onPressed: _working ? null : () => _export(scenes: false),
              ),
            ),
            HcRow(
              icon: Icons.file_download_outlined,
              label: 'Import automations',
              subtitle: 'Adds the rules in the file — it does not replace what '
                  'is here. Core gives each one a new id, so importing this '
                  "house's own export leaves you with two of everything. A "
                  'rule naming a device that does not exist is refused.',
              trailing: HcButton(
                label: 'Choose file…',
                kind: HcButtonKind.ghost,
                onPressed: _working ? null : () => _import(scenes: false),
              ),
            ),
            HcRow(
              icon: Icons.palette_outlined,
              label: 'Export scenes',
              subtitle: 'Every scene and the device states it sets.',
              trailing: HcButton(
                label: 'Export',
                kind: HcButtonKind.ghost,
                onPressed: _working ? null : () => _export(scenes: true),
              ),
            ),
            HcRow(
              icon: Icons.file_download_outlined,
              label: 'Import scenes',
              subtitle: 'Adds, like automations — new ids, nothing replaced.',
              trailing: HcButton(
                label: 'Choose file…',
                kind: HcButtonKind.ghost,
                onPressed: _working ? null : () => _import(scenes: true),
              ),
            ),
          ]),
          SizedBox(height: t.space.lg),
          Row(
            children: [
              const Expanded(child: SectionLabel('Calendars')),
              HcButton(
                label: 'Upload .ics',
                icon: Icons.upload_file,
                kind: HcButtonKind.ghost,
                onPressed: _working ? null : _uploadCalendar,
              ),
              SizedBox(width: t.space.sm),
              HcButton(
                label: 'Add calendar',
                icon: Icons.add,
                kind: HcButtonKind.ghost,
                onPressed: _working ? null : _addCalendar,
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(bottom: t.space.sm),
            child: Text(
              'An automation can trigger on a calendar event. Core fetches the '
              'feed and expands recurring events itself.',
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted),
            ),
          ),
          calendars.when(
            loading: () => const HcRowsLoading(rows: 2),
            error: (e, _) => HcRowsNotice.error(
                title: 'Calendars unavailable', detail: '$e'),
            data: (list) => list.isEmpty
                ? const HcRowsNotice(
                    icon: Icons.event_outlined,
                    title: 'No calendars',
                    detail: 'Add one by URL — an .ics or webcal feed.',
                  )
                : HcRows([
                    for (final c in list)
                      _CalendarRow(
                        calendar: c,
                        onDelete: () => _deleteCalendar('${c['id']}'),
                      ),
                  ]),
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
    final status = ref.watch(systemStatusProvider).value;
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

  /// Add a calendar from a file rather than a URL.
  ///
  /// A URL only works for a feed that is reachable and stays reachable. An
  /// exported .ics — a season's fixtures, school terms, a rota someone
  /// emailed — has no URL to give.
  Future<void> _uploadCalendar() async {
    final file = await pickFile(accept: '.ics,text/calendar');
    if (file == null) return;
    setState(() {
      _working = true;
      _status = null;
    });
    try {
      final text = utf8.decode(file.bytes);
      if (!text.contains('BEGIN:VCALENDAR')) {
        setState(() => _status =
            'That does not look like an .ics file — no BEGIN:VCALENDAR in it.');
        return;
      }
      final name =
          file.name.replaceAll(RegExp(r'\.ics$', caseSensitive: false), '');
      final res =
          await ref.read(systemDataApiProvider).uploadCalendar(text, name);
      if (!mounted) return;
      setState(() =>
          _status = res.ok ? 'Added $name.' : 'Upload failed: ${res.detail}');
      if (res.ok) ref.invalidate(calendarsProvider);
    } catch (e) {
      if (mounted) setState(() => _status = 'Upload failed: $e');
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

class _CalendarRow extends StatelessWidget {
  const _CalendarRow({required this.calendar, required this.onDelete});

  final Map<String, dynamic> calendar;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final upcoming = calendar['upcoming_count'] ?? 0;
    final total = calendar['event_count'] ?? 0;

    return HcRow(
      icon: Icons.event_outlined,
      label: '${calendar['id']}',
      subtitle: '$upcoming upcoming · $total events'
          '${calendar['source_url'] != null ? ' · fetched from a URL' : ''}',
      trailing: HcIconButton(
        icon: Icons.delete_outline,
        tooltip: 'Remove',
        danger: true,
        onPressed: onDelete,
      ),
    );
  }
}
