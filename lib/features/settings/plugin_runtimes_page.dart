import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/plugin_runtimes_api.dart';
import '../../core/providers/plugin_runtimes_provider.dart';
import '../../design/components/hc_surface.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';

const _pollInterval = Duration(seconds: 10);

/// Keeps [pluginRuntimesProvider] current while this page is on screen.
final pluginRuntimesAutoRefreshProvider = Provider.autoDispose<void>((ref) {
  final timer = Timer.periodic(
      _pollInterval, (_) => ref.invalidate(pluginRuntimesProvider));
  ref.onDispose(timer.cancel);
});

/// Admitting a machine to the house.
///
/// This lives in Manage rather than on the Plugins page on purpose. A pending
/// runtime is an *unauthenticated stranger's self-description*: putting it
/// beside the plugins you already trust invites approving it as though it were
/// one of them.
class PluginRuntimesPage extends ConsumerWidget {
  const PluginRuntimesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    ref.watch(pluginRuntimesAutoRefreshProvider);
    final runtimes = ref.watch(pluginRuntimesProvider);
    final all = runtimes.value ?? const <PluginRuntimeSummary>[];
    final placements =
        ref.watch(pluginPlacementsProvider).value?.values.toList() ??
            const <PluginPlacement>[];
    final pending = all.where((r) => r.isPending).toList();
    final approved = all.where((r) => r.isApproved).toList();

    return SectionScaffold(
      title: 'Plugin runtimes',
      subtitle: 'Containers that host plugins written in other languages',
      stats: [
        if (pending.isNotEmpty)
          SectionStat(
            value: '${pending.length}',
            label: pending.length == 1 ? 'waiting' : 'waiting',
            tone: SectionTone.warn,
          ),
        SectionStat(value: '${approved.length}', label: 'approved'),
      ],
      child: Padding(
        padding: EdgeInsets.all(t.space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (runtimes.hasError)
              const _Message(
                text: 'Could not reach homeCore for the runtime list.',
                tone: _Tone.danger,
              )
            else if (runtimes.isLoading && all.isEmpty)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (pending.isNotEmpty) ...[
                Text('Waiting for a decision',
                    style:
                        t.text.subtitleStyle.copyWith(color: t.surface.onBase)),
                SizedBox(height: t.space.sm),
                for (final r in pending) _PendingCard(runtime: r),
                SizedBox(height: t.space.lg),
              ],
              Text('Approved',
                  style:
                      t.text.subtitleStyle.copyWith(color: t.surface.onBase)),
              SizedBox(height: t.space.sm),
              if (approved.isEmpty)
                _Message(
                  text: pending.isEmpty
                      ? 'No runtimes have joined. Start a runtime container '
                          'pointing at this homeCore and it will appear here '
                          'for approval.'
                      : 'None approved yet.',
                  tone: _Tone.muted,
                )
              else
                for (final r in approved)
                  _ApprovedRow(
                    runtime: r,
                    hosts: placements
                        .where((p) => p.runtimeId == r.runtimeId)
                        .toList(),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The screen that carries the whole security of open enrollment.
///
/// Anyone who can reach the API may ask to join; nothing is granted until an
/// administrator approves a request whose code matches the one in the
/// container's own logs. So the code is the loudest thing here, and the
/// instruction to compare it is stated rather than implied.
class _PendingCard extends ConsumerStatefulWidget {
  const _PendingCard({required this.runtime});
  final PluginRuntimeSummary runtime;

  @override
  ConsumerState<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends ConsumerState<_PendingCard> {
  bool _busy = false;
  String? _error;

  Future<void> _resolve(bool approve) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(pluginRuntimesApiProvider);
    try {
      if (approve) {
        await api.approve(widget.runtime.runtimeId);
      } else {
        await api.deny(widget.runtime.runtimeId);
      }
      ref.invalidate(pluginRuntimesProvider);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final r = widget.runtime;

    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: HcSurface(
        padding: EdgeInsets.all(t.space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.hostname.isEmpty ? r.runtimeId : r.hostname,
                style: t.text.titleStyle.copyWith(color: t.surface.onBase)),
            SizedBox(height: t.space.xs),
            Text(r.capability,
                style: t.text.bodySmallStyle
                    .copyWith(color: t.surface.onBaseMuted)),
            SizedBox(height: t.space.md),

            // The point of the screen.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Through the type ramp with `mono: true`, so it picks up the
                // skin's own mono family — the app bundles JetBrains Mono
                // precisely so glyph fallback never has to leave the house.
                // The first version hard-coded `fontFamily: 'monospace'` and
                // the code did not appear on screen at all, while the
                // instruction to compare it did. Whether the literal or a
                // stale bundle caused that was not isolated; the token is the
                // right answer either way, and a screenshot now shows the code.
                SelectableText(
                  r.code ?? '—',
                  style: t.text.resolve(t.text.display, mono: true).copyWith(
                        color: t.surface.onBase,
                        letterSpacing: 4,
                      ),
                ),
                SizedBox(width: t.space.md),
                Expanded(
                  child: Text(
                    'Compare this code with the one in your container’s '
                    'logs. If they do not match, deny — something else is '
                    'asking to join.',
                    style: t.text.bodySmallStyle
                        .copyWith(color: t.surface.onBaseMuted),
                  ),
                ),
              ],
            ),
            SizedBox(height: t.space.md),

            // Supporting evidence for the same question.
            Wrap(
              spacing: t.space.md,
              runSpacing: t.space.xs,
              children: [
                _Fact(label: 'from', value: r.sourceIp ?? 'unknown'),
                _Fact(label: 'id', value: r.runtimeId),
                _Fact(label: 'host', value: r.hostVersion),
                _Fact(label: 'sdk', value: r.sdkVersion),
                _Fact(label: 'network', value: r.networkMode),
              ],
            ),

            if (_error != null) ...[
              SizedBox(height: t.space.sm),
              _Message(text: _error!, tone: _Tone.danger),
            ],

            SizedBox(height: t.space.md),
            Row(
              children: [
                // Deny first and low-friction: it is the safe answer to a
                // request you do not recognise, and the runtime may retry.
                TextButton(
                  onPressed: _busy ? null : () => _resolve(false),
                  child: const Text('Deny'),
                ),
                SizedBox(width: t.space.sm),
                FilledButton(
                  onPressed: _busy ? null : () => _resolve(true),
                  child: Text(_busy ? 'Working…' : 'Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// An approved runtime is an ordinary plugin, managed on the plugin page like
/// any other. This row exists to say it joined and where to go next.
class _ApprovedRow extends StatelessWidget {
  const _ApprovedRow({required this.runtime, this.hosts = const []});
  final PluginRuntimeSummary runtime;

  /// What this runtime is hosting. Rows link to each plugin's own page —
  /// installing, removing and restarting are capability actions on the runtime
  /// itself, so this is a list and not a control surface.
  final List<PluginPlacement> hosts;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final r = runtime;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.xs),
      child: HcSurface(
        padding:
            EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.hostname.isEmpty ? r.runtimeId : r.hostname,
                          style: t.text.bodyStyle.copyWith(
                              fontWeight: FontWeight.w600,
                              color: t.surface.onBase)),
                      Text(r.capability,
                          style: t.text.captionStyle
                              .copyWith(color: t.surface.onBaseMuted)),
                    ],
                  ),
                ),
                if (r.pluginId != null)
                  Text(r.pluginId!,
                      style: t.text.bodySmallStyle
                          .copyWith(color: t.surface.onBaseMuted)),
              ],
            ),
            // An approved runtime hosting nothing is the normal state right
            // after approval, and saying so beats an empty space that could
            // equally mean the list failed to load.
            SizedBox(height: t.space.sm),
            if (hosts.isEmpty)
              Text('Hosting nothing yet',
                  style: t.text.captionStyle
                      .copyWith(color: t.surface.onBaseMuted))
            else
              for (final h in hosts)
                InkWell(
                  onTap: () => context.go('/plugins/${h.pluginId}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text(h.pluginId,
                            style: t.text.bodySmallStyle
                                .copyWith(color: t.accent.primary)),
                        SizedBox(width: t.space.sm),
                        Text('v${h.version}',
                            style: t.text.captionStyle
                                .copyWith(color: t.surface.onBaseMuted)),
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

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ',
            style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
        Text(value,
            style: t.text.captionStyle.copyWith(color: t.surface.onBase)),
      ],
    );
  }
}

enum _Tone { muted, danger }

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.tone});
  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Text(
      text,
      style: t.text.bodySmallStyle.copyWith(
        color: tone == _Tone.danger ? t.accent.danger : t.surface.onBaseMuted,
      ),
    );
  }
}
