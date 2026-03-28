import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/device_state.dart';
import '../../core/models/scene.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/name_resolver_provider.dart';
import '../../core/providers/scenes_provider.dart';
import '../../shared/widgets/filter_bar.dart';
import '../../shared/widgets/skeleton.dart';

// ── Scene filter state ────────────────────────────────────────────────────────

class _SceneFilter {
  final String search;
  final String type; // 'all' | 'native' | 'plugin'
  final String sort; // 'name_asc' | 'name_desc'

  const _SceneFilter({this.search = '', this.type = 'all', this.sort = 'name_asc'});

  _SceneFilter copyWith({String? search, String? type, String? sort}) =>
      _SceneFilter(
          search: search ?? this.search,
          type: type ?? this.type,
          sort: sort ?? this.sort);
}

final _sceneFilterProvider =
    StateProvider<_SceneFilter>((_) => const _SceneFilter());

// ---------------------------------------------------------------------------
// Unified display model
// ---------------------------------------------------------------------------

class _DisplayScene {
  final String id;
  final String name;
  /// true = plugin-managed scene device; false = HomeCore-native scene
  final bool isPlugin;
  final List<String> deviceIds;

  _DisplayScene.native(SceneModel s)
      : id = s.id,
        name = s.name,
        isPlugin = false,
        deviceIds = s.states.keys.toList();

  _DisplayScene.plugin(DeviceState d)
      : id = d.id,
        name = d.displayName,
        isPlugin = true,
        deviceIds = const [];
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class ScenesPage extends ConsumerStatefulWidget {
  const ScenesPage({super.key});

  @override
  ConsumerState<ScenesPage> createState() => _ScenesPageState();
}

class _ScenesPageState extends ConsumerState<ScenesPage> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      ref
          .read(_sceneFilterProvider.notifier)
          .update((f) => f.copyWith(search: _searchCtrl.text));
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_DisplayScene> _applyFilter(List<_DisplayScene> scenes, _SceneFilter f) {
    var out = scenes.where((s) {
      if (f.search.isNotEmpty &&
          !s.name.toLowerCase().contains(f.search.toLowerCase())) return false;
      if (f.type == 'native' && s.isPlugin) return false;
      if (f.type == 'plugin' && !s.isPlugin) return false;
      return true;
    }).toList();

    if (f.sort == 'name_desc') {
      out.sort((a, b) => b.name.compareTo(a.name));
    } else {
      out.sort((a, b) => a.name.compareTo(b.name));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final nativeAsync = ref.watch(scenesProvider);
    final devicesAsync = ref.watch(devicesProvider);
    final activatedTimes = ref.watch(sceneActivatedTimesProvider);
    final resolver = ref.watch(deviceNameResolverProvider);
    final filter = ref.watch(_sceneFilterProvider);

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
        onPressed: () => context.push('/scenes/new'),
        tooltip: 'New scene',
        child: const Icon(Icons.add),
      ),
      body: isLoading
          ? const SkeletonList(count: 6)
          : error != null
              ? Center(child: Text('Error: $error'))
              : _buildList(
                  context,
                  ref,
                  nativeAsync.valueOrNull ?? [],
                  devicesAsync.valueOrNull ?? [],
                  activatedTimes,
                  resolver,
                  filter,
                ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<SceneModel> native,
    List<DeviceState> allDevices,
    Map<String, DateTime> activatedTimes,
    DeviceNameResolver resolver,
    _SceneFilter filter,
  ) {
    final pluginScenes =
        allDevices.where((d) => d.deviceType == 'scene').toList();

    final allScenes = [
      ...native.map(_DisplayScene.native),
      ...pluginScenes.map(_DisplayScene.plugin),
    ];

    final scenes = _applyFilter(allScenes, filter);

    if (allScenes.isEmpty) {
      return const Center(
          child: Text('No scenes yet.\nTap + to create one.',
              textAlign: TextAlign.center));
    }

    return Column(
      children: [
        FilterBar(
          searchController: _searchCtrl,
          searchHint: 'Search scenes…',
          countLabel: 'Showing ${scenes.length} of ${allScenes.length}',
          chips: [
            for (final t in [
              ('all', 'All'),
              ('native', 'Native'),
              ('plugin', 'Plugin'),
            ])
              FilterChip(
                label: Text(t.$2, style: const TextStyle(fontSize: 11)),
                selected: filter.type == t.$1,
                onSelected: (_) => ref
                    .read(_sceneFilterProvider.notifier)
                    .update((f) => f.copyWith(type: t.$1)),
                visualDensity: VisualDensity.compact,
              ),
          ],
          trailing: DropdownButton<String>(
            value: filter.sort,
            underline: const SizedBox(),
            isDense: true,
            items: const [
              DropdownMenuItem(
                  value: 'name_asc',
                  child: Text('Name A→Z', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(
                  value: 'name_desc',
                  child: Text('Name Z→A', style: TextStyle(fontSize: 12))),
            ],
            onChanged: (v) => ref
                .read(_sceneFilterProvider.notifier)
                .update((f) => f.copyWith(sort: v)),
          ),
        ),
        _ListHeader(),
        const Divider(height: 1),
        Expanded(
          child: scenes.isEmpty
              ? const Center(child: Text('No scenes match the filter.'))
              : ListView.separated(
                  itemCount: scenes.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 16),
                  itemBuilder: (context, i) => _SceneRow(
                    scene: scenes[i],
                    lastActivated: activatedTimes[scenes[i].id],
                    resolver: resolver,
                  ),
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Column header
// ---------------------------------------------------------------------------

class _ListHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.outline,
          fontWeight: FontWeight.w600,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('NAME', style: style)),
          Expanded(flex: 3, child: Text('DEVICES', style: style)),
          Expanded(flex: 2, child: Text('LAST ACTIVATED', style: style)),
          SizedBox(width: 120, child: Text('ACTIONS', style: style)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene row
// ---------------------------------------------------------------------------

class _SceneRow extends ConsumerStatefulWidget {
  final _DisplayScene scene;
  final DateTime? lastActivated;
  final DeviceNameResolver resolver;
  const _SceneRow(
      {required this.scene, this.lastActivated, required this.resolver});

  @override
  ConsumerState<_SceneRow> createState() => _SceneRowState();
}

class _SceneRowState extends ConsumerState<_SceneRow> {
  bool _activating = false;
  bool _expanded = false;

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _activate() async {
    setState(() => _activating = true);
    try {
      if (widget.scene.isPlugin) {
        await ref
            .read(devicesApiProvider)
            .setDeviceState(widget.scene.id, {'activate': true});
      } else {
        await ref.read(scenesApiProvider).activateScene(widget.scene.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.scene.name} activated')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete scene?'),
        content: Text('Delete "${widget.scene.name}"?'),
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
    if (ok == true && mounted) {
      await ref.read(scenesApiProvider).deleteScene(widget.scene.id);
      ref.invalidate(scenesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scene;
    final deviceNames = s.deviceIds
        .take(3)
        .map((id) => widget.resolver.resolve(id))
        .join(', ');
    final overflow =
        s.deviceIds.length > 3 ? ' +${s.deviceIds.length - 3}' : '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: s.isPlugin ? null : () => context.push('/scenes/${s.id}'),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Name
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Icon(
                        Icons.movie_creation_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.name,
                          style: Theme.of(context).textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!s.isPlugin && s.deviceIds.isNotEmpty)
                        IconButton(
                          icon: Icon(
                            _expanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 16,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          tooltip: 'Show devices',
                        ),
                    ],
                  ),
                ),
                // Devices
                Expanded(
                  flex: 3,
                  child: s.isPlugin
                      ? Text('Plugin scene',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .secondary))
                      : Text(
                          s.deviceIds.isEmpty
                              ? '—'
                              : '$deviceNames$overflow',
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                // Last activated
                Expanded(
                  flex: 2,
                  child: Text(
                    widget.lastActivated != null
                        ? _relativeTime(widget.lastActivated!)
                        : '—',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline),
                  ),
                ),
                // Actions
                SizedBox(
                  width: 120,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _activating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : FilledButton.tonal(
                              onPressed: _activate,
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size(72, 32),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10)),
                              child: const Text('Run',
                                  style: TextStyle(fontSize: 12)),
                            ),
                      if (!s.isPlugin) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16),
                          onPressed: _delete,
                          tooltip: 'Delete',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Expanded device list
        if (_expanded && s.deviceIds.isNotEmpty)
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            padding: const EdgeInsets.only(left: 42, right: 16, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: s.deviceIds
                  .map((id) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '• ${widget.resolver.resolve(id)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}
