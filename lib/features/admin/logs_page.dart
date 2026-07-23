import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/logs_api.dart';
import '../../core/models/log_entry.dart';
import '../../core/providers/client_error_log_provider.dart';
import '../../core/providers/time_display_provider.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';

final _logsApiProvider = Provider.autoDispose<LogsApi>((ref) {
  final api = LogsApi();
  ref.onDispose(api.dispose);
  return api;
});

class LogsPage extends ConsumerWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final errors = ref.watch(clientErrorLogProvider).length;
    return SectionScaffold(
      title: 'Logs',
      stats: [
        SectionStat(
          value: '$errors',
          label: 'client errors',
          tone: errors > 0 ? SectionTone.danger : SectionTone.neutral,
        ),
      ],
      child: DefaultTabController(
        length: 2,
        child: Builder(builder: (context) {
          final t = HcTokens.of(context);
          return Column(
            children: [
              TabBar(
                labelColor: t.accent.active,
                unselectedLabelColor: t.surface.onBaseMuted,
                indicatorColor: t.accent.active,
                dividerColor: t.stroke.hairline,
                tabs: const [
                  Tab(text: 'Server'),
                  Tab(text: 'Client Errors'),
                ],
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    _ServerLogsPage(),
                    _ClientErrorsTab(),
                  ],
                ),
              ),
            ],
          );
        }),
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
              _scrollController
                  .jumpTo(_scrollController.position.maxScrollExtent);
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
    final t = HcTokens.of(context);
    var filtered =
        _entries.where((e) => e.severity >= _levelSeverity(_minLevel)).toList();
    if (_moduleFilter.isNotEmpty) {
      final q = _moduleFilter.toLowerCase();
      filtered =
          filtered.where((e) => e.target.toLowerCase().contains(q)).toList();
    }

    return Column(
      children: [
        // Toolbar
        Container(
          color: t.surface.raised,
          padding: EdgeInsets.symmetric(
              horizontal: t.space.sm, vertical: t.space.xs),
          child: Row(
            children: [
              Icon(Icons.circle,
                  size: 9,
                  color: _connected ? t.accent.active : t.accent.danger),
              const SizedBox(width: 6),
              Text(_connected ? 'Live' : 'Reconnecting…',
                  style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12)),
              SizedBox(width: t.space.md),
              SizedBox(
                width: 160,
                height: 30,
                child: TextField(
                  controller: _moduleFilterCtrl,
                  style: TextStyle(color: t.surface.onBase, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Filter module…',
                    hintStyle:
                        TextStyle(color: t.surface.onBaseMuted, fontSize: 12),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: t.stroke.hairline)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: t.accent.active)),
                    suffixIcon: _moduleFilterCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear,
                                size: 14, color: t.surface.onBaseMuted),
                            onPressed: () => _moduleFilterCtrl.clear(),
                          )
                        : null,
                  ),
                ),
              ),
              const Spacer(),
              for (final level in _levels)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _LevelChip(
                    label: level,
                    selected: _minLevel == level,
                    onTap: () => setState(() => _minLevel = level),
                  ),
                ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.delete_sweep_outlined,
                    color: t.surface.onBaseMuted),
                tooltip: 'Clear',
                onPressed: () => setState(() => _entries.clear()),
              ),
              IconButton(
                icon: Icon(
                    _autoScroll
                        ? Icons.vertical_align_bottom
                        : Icons.pause_outlined,
                    color:
                        _autoScroll ? t.accent.active : t.surface.onBaseMuted),
                tooltip: _autoScroll ? 'Auto-scroll on' : 'Auto-scroll off',
                onPressed: () => setState(() {
                  _autoScroll = !_autoScroll;
                  if (_autoScroll && _scrollController.hasClients) {
                    _scrollController
                        .jumpTo(_scrollController.position.maxScrollExtent);
                  }
                }),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: t.stroke.hairline),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _connected ? 'Waiting for log lines…' : 'Connecting…',
                    style: TextStyle(color: t.surface.onBaseMuted),
                  ),
                )
              : SelectionArea(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.symmetric(
                        horizontal: t.space.sm, vertical: t.space.xs),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => _LogRow(entry: filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(t.radius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? t.accent.active.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(t.radius.pill),
          border:
              Border.all(color: selected ? t.accent.active : t.stroke.hairline),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? t.accent.active : t.surface.onBaseMuted)),
      ),
    );
  }
}

class _ClientErrorsTab extends ConsumerWidget {
  const _ClientErrorsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final errors = ref.watch(clientErrorLogProvider);
    final isUtc = ref.watch(timeUtcProvider);

    if (errors.isEmpty) {
      return Center(
        child: Text('No client errors recorded this session.',
            style: TextStyle(color: t.surface.onBaseMuted)),
      );
    }

    return Column(
      children: [
        Container(
          color: t.surface.raised,
          padding: EdgeInsets.symmetric(
              horizontal: t.space.md, vertical: t.space.xs),
          child: Row(
            children: [
              Text('${errors.length} error(s)',
                  style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12)),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.delete_sweep_outlined,
                    color: t.surface.onBaseMuted),
                tooltip: 'Clear',
                onPressed: () =>
                    ref.read(clientErrorLogProvider.notifier).clear(),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: t.stroke.hairline),
        Expanded(
          child: SelectionArea(
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                  horizontal: t.space.sm, vertical: t.space.xs),
              itemCount: errors.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: t.stroke.hairline),
              itemBuilder: (context, i) {
                final e = errors[errors.length - 1 - i]; // newest first
                final timeStr = fmtTime(e.timestamp, utc: isUtc);
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: t.space.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(timeStr,
                              style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: t.surface.onBaseMuted)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '${e.statusCode ?? '?'} ${e.method} ${e.url}',
                              style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: t.accent.danger),
                            ),
                          ),
                        ],
                      ),
                      if (e.body.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, left: 4),
                          child: Text(e.body,
                              style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: t.surface.onBaseMuted)),
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

class _LogRow extends ConsumerWidget {
  final LogEntry entry;
  const _LogRow({required this.entry});

  Color _levelColor(HcTokens t) => switch (entry.level) {
        'ERROR' => t.accent.danger,
        'WARN' => t.accent.warn,
        'DEBUG' => t.surface.onBaseMuted,
        _ => t.surface.onBase,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final color = _levelColor(t);
    final isUtc = ref.watch(timeUtcProvider);
    final timeStr = fmtTime(entry.timestamp, utc: isUtc);

    return InkWell(
      onLongPress: () {
        final text = '[${entry.level}] ${entry.target}: ${entry.message}';
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Copied'), duration: Duration(seconds: 1)));
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
                      color: t.surface.onBaseMuted)),
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
                      color: t.surface.onBase),
                  children: [
                    TextSpan(
                      text: '${entry.target}  ',
                      style: TextStyle(color: t.surface.onBaseMuted),
                    ),
                    TextSpan(text: entry.message),
                    if (entry.fields.isNotEmpty)
                      TextSpan(
                        text:
                            '  ${entry.fields.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
                        style: TextStyle(color: t.surface.onBaseMuted),
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
