import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/automations_provider.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/components/hc_attribute_control.dart';
import '../../design/components/hc_controls.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../../shell/hc_sheet.dart';
import '../automations/rule_phrasing.dart';

/// A device, laid over the house rather than replacing it.
///
/// Shows what you actually came for: the controls, the live state, and — the
/// part no page offered before — *which automations depend on this device*.
/// That last one is the question you ask right before you rename or delete
/// something, and answering it anywhere other than here means going and looking
/// through 42 rules by hand.
///
/// The full 872-line detail page still exists behind "Open full detail". This is
/// not a replacement for it; it is the 90% you wanted without leaving home.
Future<void> showDeviceSheet(BuildContext context, String deviceId) =>
    showHcSheet<void>(
      context,
      title: 'Device',
      child: _DeviceSheet(deviceId: deviceId),
    );

class _DeviceSheet extends ConsumerWidget {
  const _DeviceSheet({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).valueOrNull ?? const [];
    final device =
        devices.where((d) => d.id == deviceId).cast<DeviceState?>().firstOrNull;

    if (device == null) {
      return Padding(
        padding: EdgeInsets.all(t.space.lg),
        child: Text('Device not found.',
            style: TextStyle(color: t.surface.onBaseMuted)),
      );
    }

    final notifier = ref.read(devicesProvider.notifier);
    final facet = facetOf(device, device.schema);
    final on = device.available && isOn(device);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          HcSheetHeader(
            title: device.displayName,
            subtitle: [
              if (device.area != null) device.area!.replaceAll('_', ' '),
              device.deviceType,
              if (!device.available) 'offline',
            ].join(' · '),
            trailing: facet.isActuator && device.available
                ? Padding(
                    padding: EdgeInsets.only(top: t.space.xs),
                    child: HcToggle(
                      value: on,
                      semanticLabel: device.displayName,
                      onChanged: (v) => notifier.command(device.id, {'on': v}),
                    ),
                  )
                : null,
          ),

          if (!device.available)
            const _Banner(
              icon: HcIcons.offline,
              message: 'This device is offline. Commands will not reach it.',
            ),

          // Controls come from the device's own schema, so a plugin that adds an
          // attribute gets a correct control for free — no per-device UI code.
          _Controls(device: device),

          _UsedBy(device: device),

          Padding(
            padding: EdgeInsets.fromLTRB(
                t.space.lg, t.space.sm, t.space.lg, t.space.lg),
            child: Row(
              children: [
                TextButton.icon(
                  icon: const Icon(HcIcons.clock, size: 14),
                  label: const Text('History'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/devices/${device.id}/history');
                  },
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/devices/${device.id}');
                  },
                  child: const Text('Open full detail'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Every writable attribute the device declares, as the control its kind calls
/// for. Read-only attributes are shown as values rather than hidden — a sensor
/// with nothing to twiddle still has something to say.
class _Controls extends ConsumerWidget {
  const _Controls({required this.device});

  final DeviceState device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final schema = device.schema;
    final notifier = ref.read(devicesProvider.notifier);

    if (schema == null || schema.attributes.isEmpty) {
      // No schema is not an error — most plugins do not ship one. Fall back to
      // whatever state the device is actually reporting.
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in device.state.entries)
              _Reading(name: e.key, value: _readable(e.value)),
          ],
        ),
      );
    }

    // `on` already has the toggle in the header; repeating it here would be two
    // controls for one fact, which is how they end up disagreeing.
    final entries =
        schema.attributes.entries.where((e) => e.key != 'on').toList();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in entries)
            Padding(
              padding: EdgeInsets.only(bottom: t.space.md),
              child: HcAttributeControl(
                name: e.key,
                schema: e.value,
                value: device.state[e.key],
                enabled: device.available,
                onCommit: e.value.writable
                    ? (v) => notifier.command(device.id, {e.key: v})
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// The automations that mention this device.
///
/// This is the question you ask before renaming or deleting something, and until
/// now the only way to answer it was to read 42 rules by hand.
class _UsedBy extends ConsumerWidget {
  const _UsedBy({required this.device});

  final DeviceState device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final rules = ref.watch(automationsProvider).valueOrNull ?? const [];
    final all = ref.watch(devicesProvider).valueOrNull ?? const <DeviceState>[];

    // Without this the sentence reads "the yolink_d88b4c0400064299 closes".
    // A rule may name a device by raw id OR canonical name, so index both.
    final names = <String, String>{
      for (final d in all) ...{
        d.id: d.displayName,
        if (d.canonicalName != null) d.canonicalName!: d.displayName,
      },
    };
    String label(String ref) => names[ref] ?? ref;

    // A rule may refer to a device by its raw id OR its canonical name — core's
    // resolver accepts both — so match on either, or the count silently lies.
    final refs = {
      device.id,
      if (device.canonicalName != null) device.canonicalName!
    };
    final using = rules.where((r) {
      final json = r.toJson().toString();
      return refs.any(json.contains);
    }).toList();

    if (using.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(t.space.lg, 0, t.space.lg, t.space.md),
        child: Text(
          'No automations use this device.',
          style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted),
        ),
      );
    }

    return Padding(
      padding:
          EdgeInsets.fromLTRB(t.space.lg, t.space.sm, t.space.lg, t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            using.length == 1
                ? 'USED BY 1 AUTOMATION'
                : 'USED BY ${using.length} AUTOMATIONS',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: t.surface.onBaseMuted,
            ),
          ),
          SizedBox(height: t.space.sm),
          for (final r in using)
            InkWell(
              onTap: () {
                Navigator.of(context).pop();
                context.push('/automations/${r.id}');
              },
              borderRadius: t.radius.smR,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: t.space.xs + 2),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: r.enabled
                            ? t.accent.success
                            : t.surface.onBaseMuted.withValues(alpha: 0.5),
                      ),
                    ),
                    SizedBox(width: t.space.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: t.surface.onBase,
                            ),
                          ),
                          Text(
                            triggerSentence(r.trigger, label: label) ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: t.surface.onBaseMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(HcIcons.caretRight,
                        size: 12, color: t.surface.onBaseMuted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A raw state value, said the way a person would say it.
///
/// `on: false` is not a reading, it is a field dump — the same habit the rule
/// sentences exist to kill.
String _readable(Object? v) => switch (v) {
      true => 'on',
      false => 'off',
      null => '—',
      _ => '$v',
    };

class _Reading extends StatelessWidget {
  const _Reading({required this.name, required this.value});

  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs),
      child: Row(
        children: [
          Text(
            name.replaceAll('_', ' '),
            style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: t.surface.onBase,
              fontFeatures: t.numericFontFeatures,
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      margin: EdgeInsets.fromLTRB(t.space.lg, 0, t.space.lg, t.space.md),
      padding: EdgeInsets.all(t.space.sm + 2),
      decoration: BoxDecoration(
        color: t.accent.warn.withValues(alpha: 0.10),
        borderRadius: t.radius.smR,
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: t.accent.warn),
          SizedBox(width: t.space.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: t.accent.warn),
            ),
          ),
        ],
      ),
    );
  }
}
