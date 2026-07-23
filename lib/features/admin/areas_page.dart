import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/device_state.dart';
import '../../core/providers/areas_provider.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/components/hc_surface.dart';
import '../../design/tokens.dart';
import 'admin_scaffold.dart';

class AreasPage extends ConsumerWidget {
  const AreasPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areasAsync = ref.watch(areasProvider);

    return AdminScaffold(
      title: 'Areas',
      subtitle: 'Rooms devices can belong to',
      actions: [
        Builder(builder: (context) {
          final t = HcTokens.of(context);
          return IconButton(
            icon: Icon(Icons.refresh, color: t.surface.onBaseMuted),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(areasProvider),
          );
        }),
        AdminHeaderAction(
          icon: Icons.add_rounded,
          label: 'Add area',
          onPressed: () => _showCreateDialog(context, ref),
        ),
      ],
      child: areasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (areas) {
          if (areas.isEmpty) {
            return _Empty(onAdd: () => _showCreateDialog(context, ref));
          }
          final sorted = [...areas]..sort((a, b) => '${a['name']}'
              .toLowerCase()
              .compareTo('${b['name']}'.toLowerCase()));
          return Builder(builder: (context) {
            final t = HcTokens.of(context);
            return ListView.separated(
              padding: EdgeInsets.all(t.space.lg),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => SizedBox(height: t.space.md),
              itemBuilder: (context, i) => _AreaCard(area: sorted[i]),
            );
          });
        },
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await _promptForName(context, title: 'Add area');
    if (name == null || name.isEmpty) return;
    try {
      await ref.read(areasApiProvider).createArea(name);
      ref.invalidate(areasProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
}

class _AreaCard extends ConsumerWidget {
  final Map<String, dynamic> area;
  const _AreaCard({required this.area});

  String get id => area['id'] as String;
  String get name => area['name'] as String;
  List<String> get deviceIds =>
      List<String>.from(area['device_ids'] as List? ?? []);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).valueOrNull ?? [];

    return HcSurface(
      padding: EdgeInsets.all(t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.meeting_room_outlined,
                size: 18, color: t.surface.onBaseMuted),
            SizedBox(width: t.space.md),
            Expanded(
              child: Text(name,
                  style: TextStyle(
                      color: t.surface.onBase,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600)),
            ),
            _IconBtn(
                icon: Icons.edit_outlined,
                tooltip: 'Rename',
                onTap: () => _rename(context, ref)),
            _IconBtn(
                icon: Icons.devices_other,
                tooltip: 'Devices',
                onTap: () => _manageDevices(context, ref, devices)),
            _IconBtn(
                icon: Icons.delete_outline,
                tooltip: 'Delete',
                danger: true,
                onTap: () => _delete(context, ref)),
          ]),
          SizedBox(height: t.space.sm),
          if (deviceIds.isEmpty)
            Padding(
              padding: EdgeInsets.only(left: t.space.lg),
              child: Text('No devices assigned',
                  style:
                      TextStyle(color: t.surface.onBaseMuted, fontSize: 12.5)),
            )
          else
            Padding(
              padding: EdgeInsets.only(left: t.space.lg),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: deviceIds.map((d) {
                  final dev = devices.cast<DeviceState?>().firstWhere(
                        (x) => x?.id == d,
                        orElse: () => null,
                      );
                  return _MiniChip(label: dev?.displayName ?? d);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final next =
        await _promptForName(context, title: 'Rename area', initial: name);
    if (next == null || next.isEmpty || next == name) return;
    try {
      await ref.read(areasApiProvider).renameArea(id, next);
      ref.invalidate(areasProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _manageDevices(
      BuildContext context, WidgetRef ref, List<DeviceState> all) async {
    final messenger = ScaffoldMessenger.of(context);
    final selected = Set<String>.from(deviceIds);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final t = HcTokens.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setS) => HcDialog(
            title: 'Devices in $name',
            actions: [
              HcButton(
                  label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
              HcButton(
                  label: 'Save',
                  kind: HcButtonKind.primary,
                  onPressed: () => Navigator.pop(ctx, true)),
            ],
            child: SizedBox(
              width: 380,
              child: all.isEmpty
                  ? Text('No devices available',
                      style: TextStyle(color: t.surface.onBaseMuted))
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: ListView(
                        shrinkWrap: true,
                        children: all.map((d) {
                          final on = selected.contains(d.id);
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: t.accent.active,
                            title: Text(d.displayName,
                                style: TextStyle(color: t.surface.onBase)),
                            subtitle: Text(d.pluginId,
                                style: TextStyle(
                                    color: t.surface.onBaseMuted,
                                    fontSize: 11)),
                            value: on,
                            onChanged: (v) => setS(() {
                              if (v == true) {
                                selected.add(d.id);
                              } else {
                                selected.remove(d.id);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ),
        );
      },
    );
    if (saved != true) return;
    try {
      await ref.read(areasApiProvider).setDevices(id, selected.toList());
      ref.invalidate(areasProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _confirmDelete(context, name);
    if (ok != true) return;
    try {
      await ref.read(areasApiProvider).deleteArea(id);
      ref.invalidate(areasProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
}

// ── shared helpers ──

Future<String?> _promptForName(BuildContext context,
    {required String title, String? initial}) async {
  final ctrl = TextEditingController(text: initial ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final t = HcTokens.of(ctx);
      void submit() => Navigator.pop(ctx, ctrl.text.trim());
      return HcDialog(
        title: title,
        actions: [
          HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
          HcButton(
              label: 'Save', kind: HcButtonKind.primary, onPressed: submit),
        ],
        child: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: t.surface.onBase),
          decoration: InputDecoration(
            labelText: 'Name',
            labelStyle: TextStyle(color: t.surface.onBaseMuted),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: t.stroke.hairline)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: t.accent.active)),
          ),
          onSubmitted: (_) => submit(),
        ),
      );
    },
  );
  ctrl.dispose();
  return result;
}

Future<bool?> _confirmDelete(BuildContext context, String name) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => HcDialog(
      title: 'Delete $name?',
      description: 'This cannot be undone.',
      actions: [
        HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
        HcButton(
            label: 'Delete',
            kind: HcButtonKind.danger,
            onPressed: () => Navigator.pop(ctx, true)),
      ],
      child: const SizedBox.shrink(),
    ),
  );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn(
      {required this.icon,
      required this.tooltip,
      required this.onTap,
      this.danger = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return IconButton(
      icon: Icon(icon,
          size: 18, color: danger ? t.accent.danger : t.surface.onBaseMuted),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: BorderRadius.circular(t.radius.pill),
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Text(label,
          style: TextStyle(color: t.surface.onBaseMuted, fontSize: 11.5)),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.meeting_room_outlined,
              size: 40, color: t.surface.onBaseMuted),
          SizedBox(height: t.space.md),
          Text('No areas yet',
              style: TextStyle(color: t.surface.onBase, fontSize: 15)),
          SizedBox(height: t.space.xs),
          Text('Group devices by room.',
              style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12.5)),
          SizedBox(height: t.space.md),
          HcButton(
              label: 'Add area',
              kind: HcButtonKind.primary,
              icon: Icons.add_rounded,
              onPressed: onAdd),
        ],
      ),
    );
  }
}
