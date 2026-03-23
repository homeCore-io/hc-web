import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/modes_api.dart';
import '../../core/models/mode_state.dart';
import '../../core/providers/modes_provider.dart';
import '../../shared/widgets/skeleton.dart';

class ModesPage extends ConsumerWidget {
  const ModesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modesAsync = ref.watch(modesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modes'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(modesProvider)),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateDialog(context, ref),
          ),
        ],
      ),
      body: modesAsync.when(
        loading: () => const SkeletonCardList(count: 4),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (modes) {
          if (modes.isEmpty) {
            return const Center(child: Text('No modes configured'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: modes.length,
            itemBuilder: (context, i) => _ModeCard(mode: modes[i]),
          );
        },
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final idCtrl = TextEditingController(text: 'mode_');
    final nameCtrl = TextEditingController();
    String kind = 'manual';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Create mode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: idCtrl,
                  decoration: const InputDecoration(
                      labelText: 'ID (must start with mode_)')),
              const SizedBox(height: 8),
              TextField(
                  controller: nameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Display name')),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: kind,
                items: const [
                  DropdownMenuItem(value: 'manual', child: Text('Manual')),
                  DropdownMenuItem(value: 'solar', child: Text('Solar')),
                ],
                onChanged: (v) => setS(() => kind = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (idCtrl.text.isEmpty || nameCtrl.text.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  await ref
                      .read(modesApiProvider)
                      .createMode(idCtrl.text, nameCtrl.text, kind);
                  ref.invalidate(modesProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: $e')));
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    idCtrl.dispose();
    nameCtrl.dispose();
  }
}

class _ModeCard extends ConsumerStatefulWidget {
  final ModeState mode;
  const _ModeCard({required this.mode});

  @override
  ConsumerState<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends ConsumerState<_ModeCard> {
  late double _onOffset;
  late double _offOffset;

  @override
  void initState() {
    super.initState();
    _onOffset = widget.mode.onOffsetMinutes.toDouble();
    _offOffset = widget.mode.offOffsetMinutes.toDouble();
  }

  Future<void> _deleteMode() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${widget.mode.displayName}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(modesApiProvider).deleteMode(widget.mode.id);
        ref.invalidate(modesProvider);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSolar = widget.mode.kind == 'solar';
    final isNight = widget.mode.id == 'mode_night';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.mode.displayName,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(isSolar ? 'Solar' : 'Manual',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              )),
              if (!isSolar)
                Switch(
                  value: widget.mode.on,
                  onChanged: (val) async {
                    await ref
                        .read(modesApiProvider)
                        .setModeOn(widget.mode.id, val);
                    ref.invalidate(modesProvider);
                  },
                )
              else
                Chip(
                  label: Text(widget.mode.on ? 'NIGHT' : 'DAY'),
                  backgroundColor: widget.mode.on
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.secondaryContainer,
                ),
              if (!isNight)
                IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _deleteMode),
            ]),
            if (isSolar) ...[
              const Divider(),
              if (widget.mode.sunsetToday != null)
                _InfoRow('Sunset today', widget.mode.sunsetToday!),
              if (widget.mode.sunriseToday != null)
                _InfoRow('Sunrise today', widget.mode.sunriseToday!),
              if (widget.mode.effectiveOn != null)
                _InfoRow('Effective ON', widget.mode.effectiveOn!),
              if (widget.mode.effectiveOff != null)
                _InfoRow('Effective OFF', widget.mode.effectiveOff!),
              const SizedBox(height: 8),
              Text('ON offset: ${_onOffset.round()} min',
                  style: Theme.of(context).textTheme.bodySmall),
              Slider(
                value: _onOffset.clamp(-120, 120),
                min: -120,
                max: 120,
                divisions: 48,
                onChanged: (v) => setState(() => _onOffset = v),
                onChangeEnd: (v) async {
                  await ref.read(modesApiProvider).setOffset(
                      widget.mode.id, 'on_offset_minutes', v.round());
                  ref.invalidate(modesProvider);
                },
              ),
              Text('OFF offset: ${_offOffset.round()} min',
                  style: Theme.of(context).textTheme.bodySmall),
              Slider(
                value: _offOffset.clamp(-120, 120),
                min: -120,
                max: 120,
                divisions: 48,
                onChanged: (v) => setState(() => _offOffset = v),
                onChangeEnd: (v) async {
                  await ref.read(modesApiProvider).setOffset(
                      widget.mode.id, 'off_offset_minutes', v.round());
                  ref.invalidate(modesProvider);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(
              width: 120,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall)),
          Text(value),
        ]),
      );
}
