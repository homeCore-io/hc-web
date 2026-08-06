import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/audit_api.dart';
import '../../core/providers/audit_provider.dart';
import '../../core/providers/time_display_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/components/hc_surface.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';
import 'audit_phrasing.dart';

/// Who did what to this house, and whether it worked.
///
/// Core has kept an audit trail since auth landed and no Flutter screen has
/// ever read it — the only way to see a refused sign-in was the Leptos UI. It
/// is deliberately the first Administration screen to land because it depends
/// on nothing: one GET, no schema work, no config plumbing.
///
/// Two rules shape the layout. **Denied is why you came** — a refused sign-in
/// or a rejected scope is the reason anyone opens an audit log, so it is a
/// one-tap filter and it is coloured. And **the raw event type always shows**:
/// this is a record, so the sentence is a convenience on top of
/// `auth.login`, never a replacement for it.
class AuditPage extends ConsumerStatefulWidget {
  const AuditPage({super.key});

  @override
  ConsumerState<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends ConsumerState<AuditPage> {
  /// Filters applied *here*, over what the query returned: core matches
  /// `event_type` exactly, so `auth` — a prefix of `auth.login`, not a value —
  /// cannot be a query. The result and the time bound are server-side and live
  /// on the notifier.
  String? _class;
  String _search = '';
  _Range _range = _Range.week;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(auditProvider);
    final filter = ref.read(auditProvider.notifier).filter;
    final all = async.value ?? const <AuditEntry>[];
    final shown = _apply(all);
    final denied = all.where((e) => e.denied).length;

    return SectionScaffold(
      title: 'Audit',
      subtitle: 'Every privileged action, and every one that was refused',
      stats: [
        SectionStat(value: '${all.length}', label: 'events'),
        if (denied > 0)
          SectionStat(
              value: '$denied', label: 'denied', tone: SectionTone.danger),
      ],
      actions: [
        Builder(builder: (context) {
          final t = HcTokens.of(context);
          return IconButton(
            icon: Icon(Icons.refresh, color: t.surface.onBaseMuted),
            tooltip: 'Refresh',
            onPressed: () => ref.read(auditProvider.notifier).reload(),
          );
        }),
      ],
      child: Builder(builder: (context) {
        final t = HcTokens.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Filters(
              classes: _classesIn(all),
              activeClass: _class,
              denied: filter.result == 'denied',
              range: _range,
              onClass: (c) => setState(() => _class = c),
              onDenied: (v) => ref.read(auditProvider.notifier).apply(
                    AuditFilter(
                      result: v ? 'denied' : null,
                      from: filter.from,
                      limit: filter.limit,
                    ),
                  ),
              onRange: (r) {
                setState(() => _range = r);
                ref.read(auditProvider.notifier).apply(
                      AuditFilter(
                          result: filter.result, from: r.since(), limit: 500),
                    );
              },
              onSearch: (q) => setState(() => _search = q),
            ),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _Error('$e'),
                data: (_) => shown.isEmpty
                    ? _Empty(narrowed: all.isNotEmpty)
                    : _Timeline(entries: shown),
              ),
            ),
            if (all.length >= filter.limit)
              Padding(
                padding:
                    EdgeInsets.fromLTRB(t.space.lg, 0, t.space.lg, t.space.sm),
                // Say so rather than let a truncated page read as the whole
                // record — the difference matters on a page people use to
                // decide nothing happened.
                child: Text(
                  'Showing the most recent ${filter.limit}. Narrow the range '
                  'to see further back.',
                  style: t.text.bodySmallStyle
                      .copyWith(color: t.surface.onBaseMuted),
                ),
              ),
          ],
        );
      }),
    );
  }

  List<AuditEntry> _apply(List<AuditEntry> rows) {
    final q = _search.trim().toLowerCase();
    return [
      for (final e in rows)
        if (_class == null || e.eventClass == _class)
          if (q.isEmpty ||
              e.actorLabel.toLowerCase().contains(q) ||
              e.eventType.toLowerCase().contains(q) ||
              (e.targetId ?? '').toLowerCase().contains(q) ||
              (e.ip ?? '').contains(q))
            e,
    ];
  }

  List<String> _classesIn(List<AuditEntry> rows) {
    // Built from what came back, not from a hardcoded list: a new event class
    // in core should appear here without a client release, and a class this
    // house has never produced should not offer an always-empty chip.
    final seen = <String>{for (final e in rows) e.eventClass}..remove('');
    return seen.toList()..sort();
  }
}

enum _Range {
  day('24 hours', Duration(days: 1)),
  week('7 days', Duration(days: 7)),
  month('30 days', Duration(days: 30)),
  all('All', null);

  const _Range(this.label, this.window);
  final String label;
  final Duration? window;

  /// Truncated to the minute so the value is stable across rebuilds: a bound
  /// that moves every microsecond makes every request a different request.
  DateTime? since() {
    if (window == null) return null;
    final t = DateTime.now().toUtc().subtract(window!);
    return DateTime.utc(t.year, t.month, t.day, t.hour, t.minute);
  }
}

// ── filters ─────────────────────────────────────────────────────────────────

class _Filters extends StatelessWidget {
  const _Filters({
    required this.classes,
    required this.activeClass,
    required this.denied,
    required this.range,
    required this.onClass,
    required this.onDenied,
    required this.onRange,
    required this.onSearch,
  });

  final List<String> classes;
  final String? activeClass;
  final bool denied;
  final _Range range;
  final ValueChanged<String?> onClass;
  final ValueChanged<bool> onDenied;
  final ValueChanged<_Range> onRange;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space.lg, 0, t.space.lg, t.space.md),
      child: Wrap(
        spacing: t.space.xs,
        runSpacing: t.space.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Chip(
            label: 'All events',
            active: activeClass == null,
            onTap: () => onClass(null),
          ),
          for (final c in classes)
            _Chip(
              label: auditClassLabel(c),
              active: activeClass == c,
              onTap: () => onClass(activeClass == c ? null : c),
            ),
          SizedBox(width: t.space.sm),
          _Chip(
            label: 'Denied only',
            active: denied,
            danger: true,
            onTap: () => onDenied(!denied),
          ),
          SizedBox(width: t.space.sm),
          for (final r in _Range.values)
            _Chip(
              label: r.label,
              active: range == r,
              subtle: true,
              onTap: () => onRange(r),
            ),
          SizedBox(width: t.space.sm),
          SizedBox(
            width: 210,
            child: TextField(
              onChanged: onSearch,
              style: t.text.bodyStyle,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Actor, event, target or IP',
                prefixIcon: Icon(Icons.search, size: 16),
                prefixIconConstraints:
                    BoxConstraints(minWidth: 34, minHeight: 30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
    this.danger = false,
    this.subtle = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool danger;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final accent = danger ? t.accent.danger : t.accent.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: t.motion.d(t.motion.fast),
        padding: EdgeInsets.symmetric(horizontal: t.space.sm + 2, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? accent.withValues(alpha: 0.14)
              : (subtle ? Colors.transparent : t.surface.raised),
          borderRadius: BorderRadius.circular(t.radius.pill),
          border: Border.all(
            color: active ? accent : t.stroke.hairline,
          ),
        ),
        child: Text(
          label,
          style: t.text.bodySmallStyle.copyWith(
              fontWeight: FontWeight.w600,
              color: active ? accent : t.surface.onBaseMuted),
        ),
      ),
    );
  }
}

// ── the timeline ────────────────────────────────────────────────────────────

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.entries});
  final List<AuditEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final utc = ref.watch(timeUtcProvider);
    final days = groupByDay(entries, utc: utc);

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(t.space.lg, 0, t.space.lg, t.space.lg),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(2, t.space.md, 0, t.space.xs),
              child: Text(
                day.label,
                style: t.text.captionStyle.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: t.surface.onBaseMuted),
              ),
            ),
            for (final e in day.entries) _Row(entry: e, utc: utc),
          ],
        );
      },
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({required this.entry, required this.utc});
  final AuditEntry entry;
  final bool utc;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final e = widget.entry;
    final tone = e.denied
        ? t.accent.danger
        : (e.failed ? t.accent.warn : t.surface.onBaseMuted);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: HcSurface(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: t.space.md, vertical: t.space.sm),
                child: Row(
                  children: [
                    SizedBox(
                      width: 62,
                      child: Text(
                        fmtTime(e.at, utc: widget.utc),
                        style: t.text.bodySmallStyle.copyWith(
                            color: t.surface.onBaseMuted,
                            fontFeatures: t.numericFontFeatures),
                      ),
                    ),
                    SizedBox(width: t.space.sm),
                    Icon(auditActorIcon(e.actorType),
                        size: 15, color: t.surface.onBaseMuted),
                    SizedBox(width: t.space.xs),
                    SizedBox(
                      width: 132,
                      child: Text(
                        auditActorName(e),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.text.bodySmallStyle
                            .copyWith(color: t.surface.onBaseMuted),
                      ),
                    ),
                    SizedBox(width: t.space.sm),
                    Expanded(
                      child: Text(
                        auditPhrase(e),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            t.text.bodyStyle.copyWith(color: t.surface.onBase),
                      ),
                    ),
                    SizedBox(width: t.space.sm),
                    _ResultPill(result: e.result, tone: tone),
                    Icon(
                      _open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 17,
                      color: t.surface.onBaseMuted,
                    ),
                  ],
                ),
              ),
            ),
            if (_open) _Detail(entry: e, utc: widget.utc),
          ],
        ),
      ),
    );
  }
}

class _ResultPill extends StatelessWidget {
  const _ResultPill({required this.result, required this.tone});
  final String result;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final ok = result == 'success';
    return Container(
      margin: EdgeInsets.only(right: t.space.xs),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.radius.pill),
        border: Border.all(
            color: ok ? t.stroke.hairline : tone.withValues(alpha: 0.5)),
      ),
      child: Text(
        result,
        style: t.text.captionStyle.copyWith(
            fontWeight: FontWeight.w700,
            color: ok ? t.surface.onBaseMuted : tone),
      ),
    );
  }
}

/// The whole row, expanded. Nothing is computed here — every line is a field
/// core recorded, and a field it did not record is simply absent.
class _Detail extends StatelessWidget {
  const _Detail({required this.entry, required this.utc});
  final AuditEntry entry;
  final bool utc;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final e = entry;
    final rows = <(String, String)>[
      ('Event', e.eventType),
      ('When', '${e.at.toLocal()}'),
      ('Actor', '${humanize(e.actorType)} · ${e.actorLabel}'),
      if (e.actorId != null) ('Actor ID', e.actorId!),
      if (e.targetKind != null || e.targetId != null)
        ('Target', [e.targetKind, e.targetId].whereType<String>().join(' · ')),
      if (e.scopeUsed != null) ('Scope', e.scopeUsed!),
      if (e.ip != null) ('Address', e.ip!),
      if (e.userAgent != null) ('Client', e.userAgent!),
      if (e.correlationId != null) ('Correlation', e.correlationId!),
      for (final d in (e.detail ?? const {}).entries)
        (humanize(d.key), auditDetailValue(d.value)),
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.stroke.hairline)),
        color: t.surface.sunken,
      ),
      padding:
          EdgeInsets.fromLTRB(t.space.md, t.space.sm, t.space.md, t.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(r.$1,
                        style: t.text.bodySmallStyle
                            .copyWith(color: t.surface.onBaseMuted)),
                  ),
                  Expanded(
                    child: SelectableText(
                      r.$2,
                      style: t.text.bodySmallStyle.copyWith(
                          color: t.surface.onBase,
                          fontFeatures: t.numericFontFeatures),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── empty / error ───────────────────────────────────────────────────────────

class _Empty extends StatelessWidget {
  const _Empty({required this.narrowed});
  final bool narrowed;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(t.space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_toggle_off,
                size: 30, color: t.surface.onBaseMuted),
            SizedBox(height: t.space.sm),
            Text(
              narrowed ? 'Nothing matches these filters' : 'No events recorded',
              style: t.text.subtitleStyle.copyWith(color: t.surface.onBase),
            ),
            const SizedBox(height: 4),
            Text(
              narrowed
                  ? 'Widen the range or clear a filter.'
                  : 'Signing in, changing config and managing users all land here.',
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    // 403 is the interesting one: the endpoint is scope-gated, so a signed-in
    // non-admin lands here and deserves the reason rather than a red string.
    final forbidden = message.contains('403') || message.contains('audit:read');
    return Center(
      child: Padding(
        padding: EdgeInsets.all(t.space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(forbidden ? Icons.lock_outline : Icons.error_outline,
                size: 30, color: t.accent.danger),
            SizedBox(height: t.space.sm),
            Text(
              forbidden ? 'You cannot read the audit log' : 'Audit unavailable',
              style: t.text.subtitleStyle.copyWith(color: t.surface.onBase),
            ),
            const SizedBox(height: 4),
            Text(
              forbidden
                  ? 'It needs the audit:read scope — Admin and Observer have it.'
                  : message,
              textAlign: TextAlign.center,
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted),
            ),
          ],
        ),
      ),
    );
  }
}
