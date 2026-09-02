import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/devices/scene_state.dart';
import '../../core/models/device_state.dart';
import '../../core/models/plugin_entry.dart';
import '../../core/models/scene.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/plugins_provider.dart';
import '../../core/providers/scenes_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/components/hc_scene_chip.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/area_power_toggle.dart';
import '../../shared/widgets/section_group.dart';
import '../../shared/widgets/section_scaffold.dart';
import '../../shared/widgets/section_toolbar.dart';
import '../../shared/widgets/skeleton.dart';

// ── Filter state ───────────────────────────────────────────────────────────────

class _SceneFilter {
  final String search;
  final String source; // 'all' | 'custom' | <pluginId>
  final bool descending;
  const _SceneFilter(
      {this.search = '', this.source = 'all', this.descending = false});
  _SceneFilter copyWith({String? search, String? source, bool? descending}) =>
      _SceneFilter(
          search: search ?? this.search,
          source: source ?? this.source,
          descending: descending ?? this.descending);
}

class _Filter extends Notifier<_SceneFilter> {
  @override
  _SceneFilter build() => const _SceneFilter();

  void setSearch(String text) => state = state.copyWith(search: text);
  void setSource(String source) => state = state.copyWith(source: source);
  void flipOrder() => state = state.copyWith(descending: !state.descending);
}

final _filterProvider = NotifierProvider<_Filter, _SceneFilter>(_Filter.new);

// ── Display + group models ─────────────────────────────────────────────────────

const _kNative = 'homecore';

// The two helpers that used to live here — `_boolAttr` and `_sceneActive` —
// moved to `core/devices/scene_state.dart` when a drawn scene button needed
// the same answers. Two places deciding what "active" means would be two
// answers to one question.

class _DisplayScene {
  final String id;
  final String name;
  final bool isPlugin;
  final String source; // pluginId, or 'homecore' for native
  final String? area; // slug, or null when no single room
  final bool active;
  final String? groupKind; // 'room' | 'zone' | null

  _DisplayScene({
    required this.id,
    required this.name,
    required this.isPlugin,
    required this.source,
    required this.area,
    required this.active,
    required this.groupKind,
  });
}

class _Group {
  _Group({
    required this.key,
    required this.title,
    required this.isRoom,
    required this.isZone,
    required this.areaSlug,
  });
  final String key; // collapse id suffix
  final String title;
  final bool isRoom;
  final bool isZone;
  final String? areaSlug;
  final List<_DisplayScene> scenes = [];
}

// ── Page ───────────────────────────────────────────────────────────────────────

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
    _searchCtrl.addListener(
        () => ref.read(_filterProvider.notifier).setSearch(_searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// A native scene's room is the area its members agree on — one shared area,
  /// or none.
  String? _nativeArea(SceneModel s, Map<String, DeviceState> byId) {
    final areas = s.states.keys
        .map((id) => byId[id]?.effectiveArea)
        .where((a) => a != null && a.isNotEmpty)
        .toSet();
    return areas.length == 1 ? areas.first : null;
  }

  List<_DisplayScene> _display(
      List<SceneModel> native, List<DeviceState> devices) {
    final byId = {for (final d in devices) d.id: d};
    return [
      for (final s in native)
        _DisplayScene(
          id: s.id,
          name: s.name,
          isPlugin: false,
          source: _kNative,
          area: _nativeArea(s, byId),
          active: false,
          groupKind: null,
        ),
      for (final d in devices.where((d) => d.deviceType == 'scene'))
        _DisplayScene(
          id: d.id,
          name: d.displayName,
          isPlugin: true,
          source: d.pluginId,
          area: (d.effectiveArea?.isNotEmpty ?? false) ? d.effectiveArea : null,
          active: sceneActive(d.state),
          groupKind: d.state['group_kind'] as String?,
        ),
    ];
  }

  String _sourceName(String source, List<PluginEntry>? plugins) {
    if (source == _kNative) return 'HomeCore';
    final match = plugins?.where((p) => p.pluginId == source);
    return (match != null && match.isNotEmpty)
        ? match.first.displayName
        : humanize(source.replaceFirst('plugin.', ''));
  }

  /// Group by room (a scene's area), falling back to a source group when the
  /// scene has no room. Rooms A→Z first, then source groups A→Z.
  List<_Group> _group(List<_DisplayScene> scenes, List<PluginEntry>? plugins) {
    final groups = <String, _Group>{};
    for (final s in scenes) {
      if (s.area != null) {
        final key = 'room:${s.area}';
        final g = groups.putIfAbsent(
            key,
            () => _Group(
                  key: s.area!,
                  title: humanize(s.area!),
                  isRoom: true,
                  isZone: s.groupKind == 'zone',
                  areaSlug: s.area,
                ));
        g.scenes.add(s);
      } else {
        final key = 'src:${s.source}';
        final g = groups.putIfAbsent(
            key,
            () => _Group(
                  key: 'src_${s.source}',
                  title: _sourceName(s.source, plugins),
                  isRoom: false,
                  isZone: false,
                  areaSlug: null,
                ));
        g.scenes.add(s);
      }
    }
    final rooms = groups.values.where((g) => g.isRoom).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final sources = groups.values.where((g) => !g.isRoom).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    for (final g in [...rooms, ...sources]) {
      g.scenes
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return [...rooms, ...sources];
  }

  @override
  Widget build(BuildContext context) {
    final nativeAsync = ref.watch(scenesProvider);
    final devicesAsync = ref.watch(devicesProvider);
    final plugins = ref.watch(pluginsProvider).value;
    final filter = ref.watch(_filterProvider);

    final loaded = nativeAsync.hasValue && devicesAsync.hasValue;
    final native = nativeAsync.value ?? const <SceneModel>[];
    final devices = devicesAsync.value ?? const <DeviceState>[];
    final all = _display(native, devices);

    final roomCount =
        all.where((s) => s.area != null).map((s) => s.area).toSet().length;
    final customCount = all.where((s) => !s.isPlugin).length;
    final pluginSources =
        all.where((s) => s.isPlugin).map((s) => s.source).toSet();

    return SectionScaffold(
      title: 'Scenes',
      stats: loaded && all.isNotEmpty
          ? [
              SectionStat(value: '${all.length}', label: 'scenes'),
              if (roomCount > 0)
                SectionStat(value: '$roomCount', label: 'rooms'),
              if (customCount > 0)
                SectionStat(value: '$customCount', label: 'custom'),
            ]
          : const [],
      actions: [
        Builder(builder: (context) {
          final t = HcTokens.of(context);
          return IconButton(
            icon: Icon(Icons.refresh, color: t.surface.onBaseMuted),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(scenesProvider);
              ref.invalidate(devicesProvider);
            },
          );
        }),
        SectionHeaderAction(
          icon: Icons.add_rounded,
          label: 'New scene',
          onPressed: () => context.push('/scenes/new'),
        ),
      ],
      child: Builder(builder: (context) {
        final t = HcTokens.of(context);
        if (!loaded) return const SkeletonList(count: 6);
        if (all.isEmpty) {
          return Center(
            child: Text('No scenes yet — add one to get started.',
                style: TextStyle(color: t.surface.onBaseMuted)),
          );
        }

        // Apply source + search filter, then group.
        final filtered = all.where((s) {
          if (filter.source == 'custom' && s.isPlugin) return false;
          if (filter.source != 'all' &&
              filter.source != 'custom' &&
              s.source != filter.source) {
            return false;
          }
          if (filter.search.isNotEmpty) {
            final q = filter.search.toLowerCase();
            final room = s.area != null ? humanize(s.area!).toLowerCase() : '';
            if (!s.name.toLowerCase().contains(q) && !room.contains(q)) {
              return false;
            }
          }
          return true;
        }).toList();

        var groups = _group(filtered, plugins);
        if (filter.descending) {
          groups = groups.reversed.toList();
          for (final g in groups) {
            g.scenes.sort(
                (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
          }
        }

        final sourceChips = <Widget>[
          SectionChip(
              label: 'All',
              selected: filter.source == 'all',
              onTap: () => ref.read(_filterProvider.notifier).setSource('all')),
          if (customCount > 0)
            SectionChip(
                label: 'Custom',
                selected: filter.source == 'custom',
                onTap: () =>
                    ref.read(_filterProvider.notifier).setSource('custom')),
          for (final src in pluginSources)
            SectionChip(
                label: _sourceName(src, plugins),
                selected: filter.source == src,
                onTap: () => ref.read(_filterProvider.notifier).setSource(src)),
        ];

        return ListView(
          padding: EdgeInsets.fromLTRB(
              t.space.md, t.space.sm, t.space.md, t.space.xl),
          children: [
            SectionToolbar(
              controller: _searchCtrl,
              hint: 'Search scenes & rooms…',
              trailing: [
                SectionMenuButton(
                  label: filter.descending ? 'Z→A' : 'A→Z',
                  icon: filter.descending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  onTap: () => ref.read(_filterProvider.notifier).flipOrder(),
                ),
              ],
              chips: sourceChips,
            ),
            SizedBox(height: t.space.sm),
            if (groups.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: t.space.xl),
                child: Center(
                    child: Text('No scenes match the filter.',
                        style: TextStyle(color: t.surface.onBaseMuted))),
              )
            else
              for (final g in groups)
                for (final areaDevices in [
                  g.areaSlug != null
                      ? devices
                          .where((d) => d.effectiveArea == g.areaSlug)
                          .toList()
                      : const <DeviceState>[]
                ])
                  SectionGroup(
                    id: 'scenes:${g.key}',
                    title: g.title,
                    tag: g.isRoom ? (g.isZone ? 'Zone' : null) : 'Source',
                    tagAccent: true,
                    count: g.isRoom
                        ? '${g.scenes.length} scenes'
                        : '${g.scenes.length} · no room',
                    trailing: areaDevices.isNotEmpty
                        ? AreaPowerToggle(devices: areaDevices)
                        : null,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in g.scenes)
                          HcSceneChip(
                            name: s.name,
                            active: s.active,
                            onRun: () => _run(s),
                            onEdit: s.isPlugin
                                ? null
                                : () => context.push('/scenes/${s.id}'),
                          ),
                      ],
                    ),
                  ),
          ],
        );
      }),
    );
  }

  Future<void> _run(_DisplayScene s) async {
    try {
      if (s.isPlugin) {
        await ref
            .read(devicesApiProvider)
            .setDeviceState(s.id, {'activate': true});
      } else {
        await ref.read(scenesApiProvider).activateScene(s.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${s.name} activated')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }
}

// ── Scene chip ─────────────────────────────────────────────────────────────────
