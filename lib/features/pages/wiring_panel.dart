import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/device_slot.dart';
import '../../core/devices/scene_state.dart';
import '../../core/models/device_state.dart';
import '../../core/models/scene.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/scenes_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/tokens.dart';

/// What on this page is not wired to anything yet.
///
/// **A control pointed at nothing looks exactly like a control.** It is the
/// right size, it is in the right place, it has a name — and it does nothing,
/// which nobody discovers until they press it. That is the state a shared page
/// or a template arrives in *by design*, so the one thing that makes it usable
/// is a list of the gaps.
///
/// A bar rather than a tab, and only when there is something to say. Wiring is
/// a job you finish, not a place you work: the panel beside the canvas holds
/// what the *house* has, and this holds what this *page* is still missing.
class WiringPanel extends ConsumerStatefulWidget {
  const WiringPanel({
    super.key,
    required this.gaps,
    required this.onWire,
    required this.onSelect,
  });

  final List<WiringGap> gaps;

  /// Point one gap at something: the element, the field, the id chosen.
  final void Function(String widgetId, String field, String id) onWire;

  /// Show me the element this row is about.
  final ValueChanged<String> onSelect;

  @override
  ConsumerState<WiringPanel> createState() => _WiringPanelState();
}

class _WiringPanelState extends ConsumerState<WiringPanel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    if (widget.gaps.isEmpty) return const SizedBox.shrink();

    final n = widget.gaps.length;
    return Container(
      decoration: BoxDecoration(
        color: t.surface.sunken,
        border: Border(
          bottom: BorderSide(color: t.stroke.hairline, width: t.stroke.width),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: t.space.md, vertical: t.space.sm),
              child: Row(children: [
                Icon(Icons.cable_outlined, size: 15, color: t.accent.warn),
                SizedBox(width: t.space.sm),
                Expanded(
                  child: Text(
                    n == 1
                        ? 'One thing on this page is not wired to a device yet'
                        : '$n things on this page are not wired to a device yet',
                    style:
                        t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
                  ),
                ),
                Text(
                  _open ? 'Hide' : 'Wire them',
                  style: t.text.captionStyle.copyWith(color: t.accent.active),
                ),
                Icon(_open ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: t.accent.active),
              ]),
            ),
          ),
          if (_open)
            ConstrainedBox(
              // Bounded: a template can arrive with forty gaps, and a list that
              // pushed the canvas off the screen would be a worse problem than
              // the one it is solving.
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                padding:
                    EdgeInsets.fromLTRB(t.space.md, 0, t.space.md, t.space.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final gap in widget.gaps)
                      _GapRow(
                        gap: gap,
                        onSelect: () => widget.onSelect(gap.widgetId),
                        onWire: (id) =>
                            widget.onWire(gap.widgetId, gap.field, id),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GapRow extends ConsumerWidget {
  const _GapRow({
    required this.gap,
    required this.onSelect,
    required this.onWire,
  });

  final WiringGap gap;
  final VoidCallback onSelect;
  final ValueChanged<String> onWire;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value ?? const <DeviceState>[];
    final scenes = ref.watch(scenesProvider).value ?? const <SceneModel>[];

    // Scenes and devices are picked from different lists, and offering one for
    // the other is a wire that cannot work.
    final options = gap.scene
        ? <({String id, String label, String? sub})>[
            for (final s in scenes) (id: s.id, label: s.name, sub: null),
            for (final d in devices)
              if (isSceneDevice(d))
                (
                  id: d.id,
                  label: d.displayName,
                  sub: humanize(d.effectiveArea)
                ),
          ]
        : <({String id, String label, String? sub})>[
            for (final d in devices)
              if (!isSceneDevice(d))
                (
                  id: d.id,
                  label: d.displayName,
                  sub: humanize(d.effectiveArea)
                ),
          ]
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    return Padding(
      padding: EdgeInsets.only(bottom: t.space.xs),
      child: Row(children: [
        // What the page says belongs here. This is the whole value of a slot:
        // an empty picker says "choose a device", and this says which one.
        Expanded(
          child: InkWell(
            onTap: onSelect,
            borderRadius: t.radius.smR,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: t.space.xs),
              child: Row(children: [
                Icon(Icons.crop_free, size: 13, color: t.surface.onBaseMuted),
                SizedBox(width: t.space.xs),
                Flexible(
                  child: Text(
                    gap.label,
                    overflow: TextOverflow.ellipsis,
                    style:
                        t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
                  ),
                ),
                SizedBox(width: t.space.xs),
                Text(
                  '${humanize(gap.widgetType)} · ${gap.fieldLabel}',
                  overflow: TextOverflow.ellipsis,
                  style: t.text.captionStyle
                      .copyWith(color: t.surface.onBaseMuted),
                ),
              ]),
            ),
          ),
        ),
        SizedBox(width: t.space.sm),
        SizedBox(
          width: 210,
          child: DropdownButtonFormField<String>(
            key: ValueKey('wire-${gap.widgetId}-${gap.field}'),
            isExpanded: true,
            initialValue: null,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: options.isEmpty
                  ? (gap.scene ? 'No scenes yet' : 'No devices yet')
                  : (gap.scene ? 'Pick a scene' : 'Pick a device'),
              contentPadding: EdgeInsets.symmetric(
                  horizontal: t.space.sm, vertical: t.space.sm),
            ),
            items: [
              for (final o in options)
                DropdownMenuItem(
                  value: o.id,
                  child: Text(
                    (o.sub ?? '').isEmpty ? o.label : '${o.label} · ${o.sub}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: options.isEmpty
                ? null
                : (v) {
                    if (v != null) onWire(v);
                  },
          ),
        ),
      ]),
    );
  }
}
