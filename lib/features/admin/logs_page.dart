import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/logs_api.dart';
import '../../core/models/log_entry.dart';
import '../../core/providers/client_error_log_provider.dart';

final _logsApiProvider = Provider.autoDispose<LogsApi>((ref) {
  final api = LogsApi();
  ref.onDispose(api.dispose);
  return api;
});

class LogsPage extends ConsumerWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Logs'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Server'),
              Tab(text: 'Client Errors'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ServerLogsTab(),
            _ClientErrorsTab(),
          ],
        ),
      ),
    );
  }
}

class _ServerLogsPage extends ConsumerStatefulWidget {
  const _ServerLogsPage();

  @override
  ConsumerState<_ServerLogsPage> createState() => _ServerLogsPageState();
}

class _ServerLogsPageState extends ConsumerState<_ServerLogsPage> {
  final _scrollController = ScrollController();
  final _moduleFilterCtrl = TextEditingController();
  final List<LogEntry> _entries = [];
  StreamSubscription<LogEntry>? _sub;
  bool _autoScroll = true;
  bool _connected = false;
  String _minLevel = 'INFO';
  String _moduleFilter = '';
  static const _maxEntries = 500;

  static const _levels = ['DEBUG', 'INFO', 'WARN', 'ERROR'];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _moduleFilterCtrl.addListener(
        () => setState(() => _moduleFilter = _moduleFilterCtrl.text));
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  void _connect() {
    final api = ref.read(_logsApiProvider);
    api.connectionState.listen((c) {
      if (mounted) setState(() => _connected = c);
    });
    _sub = api.connect(level: 'debug').listen((entry) {
      if (entry.severity < _levelSeverity(_minLevel)) return;
      if (mounted) {
        setState(() {
          _entries.add(entry);
          if (_entries.length > _maxEntries) {
            _entries.removeRange(0, _entries.length - _maxEntries);
          }
        });
        if (_autoScroll) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(
                  _scrollController.position.maxScrollExtent);
            }
          });
        }
      }
    });
  }

  void _onScroll() {
    final pos = _scrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 40;
    if (atBottom != _autoScroll) {
      setState(() => _autoScroll = atBottom);
    }
  }

  int _levelSeverity(String level) => switch (level) {
        'DEBUG' => 2,
        'INFO' => 3,
        'WARN' => 4,
        'ERROR' => 5,
        _ => 3,
      };

  @override
  void dispose() {
    _sub?.cancel();
    _scrollController.dispose();
    _moduleFilterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var filtered = _entries
        .where((e) => e.severity >= _levelSeverity(_minLevel))
        .toList();
    if (_moduleFilter.isNotEmpty) {
      final q = _moduleFilter.toLowerCase();
      filtered = filtered
          .where((e) => e.target.toLowerCase().contains(q))
          .toList();
    }

    return Column(
      children: [
        // Toolbar row
        Material(
          elevation: 0,
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(
                  _connected ? Icons.circle : Icons.circle_outlined,
                  size: 10,
                  color: _connected
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 6),
                Text(
                  _connected ? 'Live' : 'Reconnecting…',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _moduleFilterCtrl,
                    decoration: InputDecoration(
                      hintText: 'Filter module…',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 8),
                      suffixIcon: _moduleFilterCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () => _moduleFilterCtrl.clear(),
                            )
                          : null,
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const Spacer(),
                for (final level in _levels)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FilterChip(
                      label: Text(level, style: const TextStyle(fontSize: 11)),
                      selected: _minLevel == level,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) =>
                          setState(() => _minLevel = level),
                    ),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'Clear',
                  onPressed: () => setState(() => _entries.clear()),
                ),
                IconButton(
                  icon: Icon(_autoScroll
                      ? Icons.vertical_align_bottom
                      : Icons.pause_outlined),
                  tooltip:
                      _autoScroll ? 'Auto-scroll on' : 'Auto-scroll off',
                  onPressed: () => setState(() {
                    _autoScroll = !_autoScroll;
                    if (_autoScroll && _scrollController.hasClients) {
                      _scrollController.jumpTo(
                          _scrollController.position.maxScrollExtent);
                    }
                  }),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _connected ? 'Waiting for log lines…' : 'Connecting…',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : SelectionArea(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) =>
                        _LogRow(entry: filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

// ── Tab wrappers ─────────────────────────────────────────────────────────────

class _ServerLogsTab extends StatelessWidget {
  const _ServerLogsTab();
  @override
  Widget build(BuildContext context) => const _ServerLogsPage();
}

class _ClientErrorsTab extends ConsumerWidget {
  const _ClientErrorsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final errors = ref.watch(clientErrorLogProvider);

    if (errors.isEmpty) {
      return const Center(child: Text('No client errors recorded this session.'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Text('${errors.length} error(s)',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: 'Clear',
                onPressed: () =>
                    ref.read(clientErrorLogProvider.notifier).clear(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SelectionArea(
            child: ListView.separated(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: errors.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final e = errors[errors.length - 1 - i]; // newest first
                final ts = e.timestamp.toLocal();
                final timeStr =
                    '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${e.statusCode ?? '?'} ${e.method} ${e.url}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color:
                                  Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                      if (e.body.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, left: 4),
                          child: Text(
                            e.body,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ── Log row ───────────────────────────────────────────────────────────────────

class _LogRow extends StatelessWidget {
  final LogEntry entry;
  const _LogRow({required this.entry});

  Color _levelColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (entry.level) {
      'ERROR' => cs.error,
      'WARN' => Colors.orange,
      'DEBUG' => cs.onSurface.withValues(alpha: 0.4),
      _ => cs.onSurface,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(context);
    final ts = entry.timestamp.toLocal();
    final timeStr =
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';

    return InkWell(
      onLongPress: () {
        final text =
            '[${entry.level}] ${entry.target}: ${entry.message}';
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 68,
              child: Text(timeStr,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5))),
            ),
            SizedBox(
              width: 44,
              child: Text(
                entry.level.length > 4
                    ? entry.level.substring(0, 4)
                    : entry.level,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color),
              ),
            ),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface),
                  children: [
                    TextSpan(
                      text: '${entry.target}  ',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5)),
                    ),
                    TextSpan(text: entry.message),
                    if (entry.fields.isNotEmpty)
                      TextSpan(
                        text:
                            '  ${entry.fields.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
