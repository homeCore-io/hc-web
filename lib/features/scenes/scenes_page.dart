import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/device_state.dart';
import '../../core/models/scene.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/scenes_provider.dart';
import '../../shared/widgets/skeleton.dart';

// ---------------------------------------------------------------------------
// Unified display model
// ---------------------------------------------------------------------------

class _DisplayScene {
  final String id;
  final String name;
  /// true = plugin-managed scene device; false = HomeCore-native scene
  final bool isPlugin;
  final int deviceCount;

  _DisplayScene.native(SceneModel s)
      : id = s.id,
        name = s.name,
        isPlugin = false,
        deviceCount = s.states.length;

  _DisplayScene.plugin(DeviceState d)
      : id = d.id,
        name = d.displayName,
        isPlugin = true,
        deviceCount = 0;
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class ScenesPage extends ConsumerWidget {
  const ScenesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nativeAsync = ref.watch(scenesProvider);
    final devicesAsync = ref.watch(devicesProvider);

    final isLoading = nativeAsync.isLoading || devicesAsync.isLoading;
    final error = nativeAsync.error ?? devicesAsync.error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scenes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(scenesProvider);
              ref.invalidate(devicesProvider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/scenes/new'),
        tooltip: 'New HomeCore scene',
        child: const Icon(Icons.add),
      ),
      body: isLoading
          ? const SkeletonCardList(count: 6)
          : error != null
              ? Center(child: Text('Error: $error'))
              : _buildGrid(context, ref, nativeAsync.valueOrNull ?? [],
                  devicesAsync.valueOrNull ?? []),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    WidgetRef ref,
    List<SceneModel> native,
    List<DeviceState> allDevices,
  ) {
    final pluginScenes =
        allDevices.where((d) => d.deviceType == 'scene').toList();

    final scenes = [
      ...native.map(_DisplayScene.native),
      ...pluginScenes.map(_DisplayScene.plugin),
    ];

    if (scenes.isEmpty) {
      return const Center(
          child: Text('No scenes yet.\nTap + to create one.',
              textAlign: TextAlign.center));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        childAspectRatio: 1.4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: scenes.length,
      itemBuilder: (context, i) => _SceneCard(scene: scenes[i]),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene card
// ---------------------------------------------------------------------------

class _SceneCard extends ConsumerWidget {
  final _DisplayScene scene;
  const _SceneCard({required this.scene});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // Plugin scenes have no editor; native scenes navigate to editor
        onTap: scene.isPlugin ? null : () => context.go('/scenes/${scene.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                    child: Text(scene.name,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis)),
                if (!scene.isPlugin)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _confirmDelete(context, ref),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ]),
              const Spacer(),
              if (!scene.isPlugin)
                Text(
                    '${scene.deviceCount} device${scene.deviceCount != 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.bodySmall)
              else
                Text('Plugin scene',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.secondary)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _activate(context, ref),
                  child: const Text('Activate'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _activate(BuildContext context, WidgetRef ref) async {
    try {
      if (scene.isPlugin) {
        await ref
            .read(devicesApiProvider)
            .setDeviceState(scene.id, {'activate': true});
      } else {
        await ref.read(scenesApiProvider).activateScene(scene.id);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${scene.name} activated')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to activate: $e')));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete scene?'),
        content: Text('Delete "${scene.name}"?'),
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
      await ref.read(scenesApiProvider).deleteScene(scene.id);
      ref.invalidate(scenesProvider);
    }
  }
}
