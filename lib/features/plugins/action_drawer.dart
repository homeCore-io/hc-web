import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/schema/plugin_capabilities.dart';
import '../../core/text/humanize.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/tokens.dart';

/// Live view of a streaming plugin action.
///
/// It is driven entirely by core's frozen stage envelope, so it works for
/// Z-Wave inclusion, Sonos discovery and whatever a plugin author writes next,
/// with no changes here:
///
///   progress       → the message + a bar
///   item           → a row, deduped by the action's `item_key`, add/update/remove
///   awaiting_user  → a prompt ("press the button on the device now")
///   warning        → a non-fatal note that stays visible
///   complete/error/canceled/timeout → terminal; the stream ends
///
/// The `awaiting_user` stage is the one that matters: Z-Wave inclusion needs the
/// user to physically press a button on the device, and without surfacing it the
/// pairing simply times out with no explanation.
class ActionDrawer extends StatefulWidget {
  const ActionDrawer({
    super.key,
    required this.action,
    required this.events,
    this.onCancel,
  });

  final PluginAction action;
  final Stream<ActionEvent> events;

  /// Only offered when the action declared `cancelable`.
  final Future<void> Function()? onCancel;

  @override
  State<ActionDrawer> createState() => _ActionDrawerState();
}

class _ActionDrawerState extends State<ActionDrawer> {
  late final StreamSubscription<ActionEvent> _sub;

  final _items = <String, ActionEvent>{};
  final _warnings = <String>[];

  ActionEvent? _latest;
  ActionStage? _terminal;
  String? _awaiting;

  @override
  void initState() {
    super.initState();
    _sub = widget.events.listen(
      _onEvent,
      onError: (Object e) => setState(() {
        _terminal = ActionStage.error;
        _latest = ActionEvent(stage: ActionStage.error, message: '$e');
      }),
    );
  }

  void _onEvent(ActionEvent e) {
    setState(() {
      _latest = e;

      switch (e.stage) {
        case ActionStage.item:
          // Deduped by the key the action nominated via `item_key`, so an
          // `update` revises the row it already produced rather than appending
          // a near-duplicate.
          final key = _keyOf(e) ?? '${_items.length}';
          if (e.op == 'remove') {
            _items.remove(key);
          } else {
            _items[key] = e;
          }

        case ActionStage.awaitingUser:
          _awaiting = e.message ?? 'Waiting for you…';

        case ActionStage.warning:
          if (e.message != null) _warnings.add(e.message!);

        case ActionStage.progress:
          // A progress frame means whatever we were waiting for happened.
          _awaiting = null;

        case _:
          break;
      }

      if (e.stage.isTerminal) {
        _terminal = e.stage;
        _awaiting = null;
      }
    });
  }

  String? _keyOf(ActionEvent e) {
    final data = e.data;
    if (data is! Map) return null;
    final k = widget.action.itemKey;
    if (k != null && data[k] != null) return '${data[k]}';
    return null;
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  /// Render a streamed item as a readable row instead of a raw map dump.
  /// Uses the action's own fields (`name`/`bridge_id`/`id`, `host`, `status`,
  /// `error`) generically, so it reads well for any plugin.
  Widget _itemTile(BuildContext context, ActionEvent e) {
    final t = HcTokens.of(context);
    final data = e.data is Map
        ? Map<String, dynamic>.from(e.data as Map)
        : const <String, dynamic>{};
    final title = e.label ??
        data['name']?.toString() ??
        data['bridge_id']?.toString() ??
        data['id']?.toString() ??
        widget.action.label;
    final subtitle = data['error']?.toString() ?? data['host']?.toString();
    final status = data['status']?.toString();

    final (statusColor, statusIcon) = switch (status) {
      'paired' || 'ok' || 'done' || 'added' => (
          t.accent.success,
          Icons.check_circle_outline
        ),
      'error' || 'failed' => (t.accent.danger, Icons.error_outline),
      'already_paired' || 'skipped' => (
          t.surface.onBaseMuted,
          Icons.info_outline
        ),
      _ => (t.surface.onBaseMuted, Icons.radio_button_unchecked),
    };

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(statusIcon, size: 16, color: statusColor),
      title: Text(title,
          style: t.text.bodyStyle.copyWith(color: t.surface.onBase)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted)),
      trailing: status == null
          ? null
          : Text(humanize(status),
              style: t.text.bodySmallStyle
                  .copyWith(color: statusColor, fontWeight: FontWeight.w600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final running = _terminal == null;

    return HcDialog(
      title: widget.action.label,
      trailing: running
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: t.accent.active),
            )
          : Icon(
              _terminal!.isFailure ? Icons.error_outline : Icons.check_circle,
              color: _terminal!.isFailure ? t.accent.danger : t.accent.success,
            ),
      actions: [
        if (running && widget.onCancel != null)
          HcButton(
            label: 'Cancel',
            onPressed: () async {
              await widget.onCancel!();
              // Guard the BuildContext, not the State: this closure captures
              // build's `context`, and the dialog can be dismissed while the
              // cancel request is still in flight.
              if (context.mounted) Navigator.pop(context);
            },
          ),
        HcButton(
          label: running ? 'Running…' : 'Close',
          kind: HcButtonKind.primary,
          onPressed: running ? null : () => Navigator.pop(context),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_awaiting != null) _awaitingBanner(context, _awaiting!),
          if (_latest?.percent case final pct?)
            Padding(
              padding: EdgeInsets.only(bottom: t.space.sm),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(t.radius.pill),
                child: LinearProgressIndicator(
                  value: (pct / 100).clamp(0.0, 1.0).toDouble(),
                  minHeight: 4,
                  backgroundColor: t.surface.sunken,
                  color: t.accent.active,
                ),
              ),
            ),
          if (_latest?.message case final msg?)
            Padding(
              padding: EdgeInsets.only(bottom: t.space.sm),
              child: Text(msg,
                  style: t.text.bodyStyle.copyWith(color: t.surface.onBase)),
            ),
          for (final w in _warnings)
            Padding(
              padding: EdgeInsets.only(bottom: t.space.xs),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 14, color: t.accent.warn),
                  SizedBox(width: t.space.sm),
                  Expanded(
                    child: Text(w,
                        style: t.text.bodySmallStyle
                            .copyWith(color: t.surface.onBaseMuted)),
                  ),
                ],
              ),
            ),
          if (_items.isNotEmpty) ...[
            Divider(color: t.stroke.hairline, height: t.space.lg),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in _items.values) _itemTile(context, e),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _awaitingBanner(BuildContext context, String message) {
    final t = HcTokens.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: t.space.md),
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: t.accent.active.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(t.radius.md),
        border: Border.all(color: t.accent.active.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.touch_app_outlined, color: t.accent.active),
          SizedBox(width: t.space.md),
          Expanded(
            child: Text(
              message,
              style: t.text.bodyStyle.copyWith(
                  color: t.accent.active, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
