import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/scene.dart';
import '../../core/providers/scenes_provider.dart';

class ScenesPage extends ConsumerWidget {
  const ScenesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scenesAsync = ref.watch(scenesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scenes'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(scenesProvider)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/scenes/new'),
        child: const Icon(Icons.add),
      ),
      body: scenesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (scenes) {
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
        },
      ),
    );
  }
}

class _SceneCard extends ConsumerWidget {
  final SceneModel scene;
  const _SceneCard({required this.scene});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceCount = scene.states.length;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/scenes/${scene.id}'),
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
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _confirmDelete(context, ref),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
              const Spacer(),
              Text('$deviceCount device${deviceCount != 1 ? 's' : ''}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await ref
                        .read(scenesApiProvider)
                        .activateScene(scene.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text('${scene.name} activated')));
                    }
                  },
                  child: const Text('Activate'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
