import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/wiring.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/tokens.dart';

/// Every wire on the page, at once.
///
/// The inspector answers "what drives this element". This answers the two
/// questions it cannot: **what does this device drive**, and **what is wired at
/// all**. On a page of forty bindings the first is unanswerable by selecting
/// things one at a time, and the second is how a page ends up with a binding
/// nobody meant to leave behind.
///
/// The house is on the left and the page is on the right, because that is the
/// direction a reading travels. A wire that runs the other way — an `on_tap`
/// action — is drawn in the writing colour and read right to left, so the two
/// kinds cannot be mistaken for each other at a glance.
///
/// Selecting a wire selects its element, which is the point: this is a way of
/// *finding* the thing that is wrong, not a second place to fix it.
class WiringView extends ConsumerWidget {
  const WiringView({
    super.key,
    required this.wires,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Wire> wires;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value ?? const <DeviceState>[];
    String nameOf(String id) =>
        devices
            .where((d) => d.id == id)
            .map((d) => d.displayName)
            .firstOrNull ??
        id;

    if (wires.isEmpty) {
      return _Empty(t: t);
    }

    // Grouped by device, because "what does this device drive" is the question
    // the inspector cannot answer at all.
    final byDevice = <String, List<Wire>>{};
    for (final w in wires) {
      byDevice.putIfAbsent(w.deviceId, () => []).add(w);
    }
    final deviceIds = byDevice.keys.toList()
      ..sort(
          (a, b) => nameOf(a).toLowerCase().compareTo(nameOf(b).toLowerCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(t.space.md, t.space.md, t.space.md, 0),
          child: Row(children: [
            Text(
              wires.length == 1
                  ? '1 wire on this page'
                  : '${wires.length} wires on this page',
              style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
            ),
            const Spacer(),
            _Key(colour: t.accent.primary, label: 'reads', t: t),
            SizedBox(width: t.space.sm),
            _Key(colour: t.accent.success, label: 'sets', t: t),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.all(t.space.md),
            itemCount: deviceIds.length,
            itemBuilder: (context, i) {
              final id = deviceIds[i];
              return _DeviceGroup(
                name: nameOf(id),
                missing: devices.every((d) => d.id != id) &&
                    byDevice[id]!.every((w) => w.key != 'go'),
                wires: byDevice[id]!,
                selectedId: selectedId,
                onSelect: onSelect,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.t});
  final HcTokens t;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsets.all(t.space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.share_outlined,
                  size: 28, color: t.surface.onBaseMuted),
              SizedBox(height: t.space.sm),
              Text('Nothing on this page is wired yet.',
                  style:
                      t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted)),
              SizedBox(height: t.space.xs),
              Text(
                'Bind a property in an element’s Data section, or give one '
                'something to do when tapped.',
                textAlign: TextAlign.center,
                style:
                    t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
              ),
            ],
          ),
        ),
      );
}

class _Key extends StatelessWidget {
  const _Key({required this.colour, required this.label, required this.t});
  final Color colour;
  final String label;
  final HcTokens t;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 2, color: colour),
          SizedBox(width: t.space.xs),
          Text(label,
              style:
                  t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
        ],
      );
}

class _DeviceGroup extends StatelessWidget {
  const _DeviceGroup({
    required this.name,
    required this.missing,
    required this.wires,
    required this.selectedId,
    required this.onSelect,
  });

  final String name;

  /// The device is not in the house any more, and something is still wired to
  /// it. Said here because this is the only surface that can say it: an element
  /// bound to a device that has gone renders as nothing in particular.
  final bool missing;
  final List<Wire> wires;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Flexible(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: t.text.bodySmallStyle.copyWith(
                  color: missing ? t.accent.warn : t.surface.onBase,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (missing) ...[
              SizedBox(width: t.space.xs),
              Text('not in this house',
                  style: t.text.captionStyle.copyWith(color: t.accent.warn)),
            ],
          ]),
          SizedBox(height: t.space.xs),
          for (final wire in wires)
            _WireRow(
              wire: wire,
              on: wire.elementId == selectedId,
              onTap: () => onSelect(wire.elementId),
            ),
        ],
      ),
    );
  }
}

/// One wire: what it comes from, what it passes through, what it lands on.
class _WireRow extends StatelessWidget {
  const _WireRow({required this.wire, required this.on, required this.onTap});

  final Wire wire;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final reads = wire.way == WireWay.reads;
    final ink = reads ? t.accent.primary : t.accent.success;

    return InkWell(
      onTap: onTap,
      borderRadius: t.radius.smR,
      child: Container(
        margin: EdgeInsets.only(bottom: t.space.xs),
        padding:
            EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.sm),
        decoration: BoxDecoration(
          color: on ? ink.withValues(alpha: .10) : t.surface.raised,
          border: Border.all(
              color: on ? ink.withValues(alpha: .5) : t.stroke.hairline),
          borderRadius: t.radius.smR,
        ),
        child: Row(children: [
          _Chip(text: humanize(wire.key), ink: ink, t: t),
          _Arrow(reads: reads, ink: ink, t: t),
          if (wire.transform case final transform?) ...[
            // The step that was buried two levels inside an inspector, and the
            // thing most likely to be why a page shows the wrong number.
            _Chip(text: transform, ink: t.surface.onBaseMuted, t: t),
            _Arrow(reads: reads, ink: ink, t: t),
          ],
          Flexible(
            child: Text(
              wire.property.isEmpty
                  ? wire.elementName
                  : '${wire.elementName} · ${humanize(wire.property)}',
              overflow: TextOverflow.ellipsis,
              style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.ink, required this.t});
  final String text;
  final Color ink;
  final HcTokens t;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: t.space.xs, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: ink.withValues(alpha: .45)),
          borderRadius: t.radius.xsR,
        ),
        child: Text(text,
            style: t.text.captionStyle
                .copyWith(color: ink, fontFamily: t.text.monoFamily)),
      );
}

/// The wire itself. Points the way the value travels, so a reading and an
/// action cannot be mistaken for one another.
class _Arrow extends StatelessWidget {
  const _Arrow({required this.reads, required this.ink, required this.t});
  final bool reads;
  final Color ink;
  final HcTokens t;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space.xs),
        child: Icon(
          reads ? Icons.east : Icons.west,
          size: 13,
          color: ink,
        ),
      );
}
