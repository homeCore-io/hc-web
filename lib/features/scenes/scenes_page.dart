import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/device_state.dart';
import '../../core/models/plugin_entry.dart';
import '../../core/models/scene.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/plugins_provider.dart';
import '../../core/providers/scenes_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/components/hc_surface.dart';
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

final _filterProvider =
    StateProvider<_SceneFilter>((_) => const _SceneFilter());

// ── Display + group models ─────────────────────────────────────────────────────

const _kNative = 'homecore';

/// Coerce an attribute to a bool, accepting the string spellings plugins use —
/// mirrors the old Leptos `bool_attr`. Returns null when the value isn't a
/// recognisable boolean, so the caller can fall through to the next key.
bool? _boolAttr(dynamic v) {
  if (v is bool) return v;
  if (v is String) {
    switch (v.trim().toLowerCase()) {
      case 'true':
      case 'on':
      case 'open':
      case 'active':
      case 'occupied':
      case 'detected':
        return true;
      case 'false':
      case 'off':
      case 'closed':
      case 'inactive':
      case 'clear':
      case 'unoccupied':
        return false;
    }
  }
  return null;
}

/// Whether a plugin scene is currently applied. Plugins disagree on the field:
/// Hue publishes `active`, Lutron publishes `on` (from the phantom-button LED),
/// others `activate`/`state`. Check them in order, first recognisable boolean
/// wins — the same resilient logic the previous (Leptos) UI used.
bool _sceneActive(Map<String, dynamic> attrs) {
  for (final k in const ['on', 'active', 'activate', 'state']) {
    final b = _boolAttr(attrs[k]);
    if (b != null) return b;
  }
  return false;
}

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
    _searchCtrl.addListener(() => ref
        .read(_filterProvider.notifier)
        .update((f) => f.copyWith(search: _searchCtrl.text)));
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
          active: _sceneActive(d.state),
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
    final plugins = ref.watch(pluginsProvider).valueOrNull;
    final filter = ref.watch(_filterProvider);

    final loaded = nativeAsync.hasValue && devicesAsync.hasValue;
    final native = nativeAsync.valueOrNull ?? const <SceneModel>[];
    final devices = devicesAsync.valueOrNull ?? const <DeviceState>[];
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
              onTap: () => ref
                  .read(_filterProvider.notifier)
                  .update((f) => f.copyWith(source: 'all'))),
          if (customCount > 0)
            SectionChip(
                label: 'Custom',
                selected: filter.source == 'custom',
                onTap: () => ref
                    .read(_filterProvider.notifier)
                    .update((f) => f.copyWith(source: 'custom'))),
          for (final src in pluginSources)
            SectionChip(
                label: _sourceName(src, plugins),
                selected: filter.source == src,
                onTap: () => ref
                    .read(_filterProvider.notifier)
                    .update((f) => f.copyWith(source: src))),
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
                  onTap: () => ref
                      .read(_filterProvider.notifier)
                      .update((f) => f.copyWith(descending: !f.descending)),
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
                          _SceneChip(
                            scene: s,
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

// ── Scene palette ──────────────────────────────────────────────────────────────

/// The colours a scene paints the room in, keyed off its name where the bridge
/// doesn't hand us the real palette. Drives the chip's dot, hover glow, and —
/// for the active scene — the drifting aurora border.
class _ScenePalette {
  const _ScenePalette(this.dot, this.gradient);
  final Color dot;
  final List<Color> gradient;
}

const _kPalettes = <String, _ScenePalette>{
  'relax': _ScenePalette(Color(0xFFFFB661),
      [Color(0xFFFFB661), Color(0xFFFF8A5B), Color(0xFFE24C4C)]),
  'read': _ScenePalette(Color(0xFFFFC97A),
      [Color(0xFFFFE3B0), Color(0xFFFFC97A), Color(0xFFFF9A5B)]),
  'concentrate': _ScenePalette(Color(0xFFBCD8FF),
      [Color(0xFFEAF2FF), Color(0xFF9DC4FF), Color(0xFF7CC4FF)]),
  'energize': _ScenePalette(Color(0xFF5BE0C0),
      [Color(0xFFDFF6FF), Color(0xFF7CC4FF), Color(0xFF4CE0D0)]),
  'nightlight': _ScenePalette(Color(0xFFC25A3A),
      [Color(0xFFC25A3A), Color(0xFF7A3B2A), Color(0xFF3A2018)]),
  'bright': _ScenePalette(Color(0xFFFFFFFF),
      [Color(0xFFFFFFFF), Color(0xFFE9EDF2), Color(0xFFBFC7D2)]),
  'dimmed':
      _ScenePalette(Color(0xFFB79A6A), [Color(0xFF6B5B45), Color(0xFF4A3F30)]),
  'savanna': _ScenePalette(Color(0xFFFF6B4A),
      [Color(0xFFFF9A5B), Color(0xFFE24C4C), Color(0xFFB03050)]),
  'aurora': _ScenePalette(Color(0xFF5BE0C0),
      [Color(0xFF5BE0C0), Color(0xFF4C9EE2), Color(0xFF7C6BFF)]),
  'blossom': _ScenePalette(Color(0xFFFF9EC4),
      [Color(0xFFFF9EC4), Color(0xFFE24C9E), Color(0xFFB03050)]),
  'twilight': _ScenePalette(Color(0xFFB98BFF),
      [Color(0xFFB98BFF), Color(0xFFFF8ABF), Color(0xFFFF8A5B)]),
  'mountain': _ScenePalette(Color(0xFFBCDCFF),
      [Color(0xFFBCDCFF), Color(0xFF7C9EE2), Color(0xFF5B6BE0)]),
  'on air':
      _ScenePalette(Color(0xFFFF5B5B), [Color(0xFFFF5B5B), Color(0xFFB03030)]),
};

_ScenePalette? _paletteFor(String name) {
  final n = name.toLowerCase();
  for (final e in _kPalettes.entries) {
    if (n.contains(e.key)) return e.value;
  }
  return null;
}

// ── Scene chip (B: colour glow · D: aurora edge when active) ─────────────────────

class _SceneChip extends StatefulWidget {
  const _SceneChip({required this.scene, required this.onRun, this.onEdit});
  final _DisplayScene scene;
  final VoidCallback onRun;
  final VoidCallback? onEdit;

  @override
  State<_SceneChip> createState() => _SceneChipState();
}

class _SceneChipState extends State<_SceneChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final s = widget.scene;
    final p = _paletteFor(s.name);
    final custom = widget.onEdit != null;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final content = _content(t, p, custom);

    // Active scene with a known palette gets the animated aurora ring (D).
    if (s.active && p != null && !reduce) {
      return _AuroraChip(palette: p, onTap: widget.onRun, child: content);
    }

    // Everything else is a colour-glow pill (B): raised HcSurface, a palette
    // dot, and a soft glow in the scene's colour on hover (persistent if the
    // scene is active but has no palette to animate).
    final glowColor = p?.dot ?? (s.active ? t.accent.active : null);
    final intensity = s.active ? 0.6 : (_hover && p != null ? 0.5 : 0.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: HcSurface(
        onTap: widget.onRun,
        glowColor: glowColor,
        glowIntensity: intensity,
        padding: EdgeInsets.fromLTRB(11, 8, custom ? 7 : 13, 8),
        child: content,
      ),
    );
  }

  Widget _content(HcTokens t, _ScenePalette? p, bool custom) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (p != null)
          _Dot(color: p.dot)
        else
          Icon(Icons.play_arrow_rounded,
              size: 14, color: t.surface.onBaseMuted),
        const SizedBox(width: 9),
        Text(widget.scene.name,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color:
                    widget.scene.active ? t.accent.active : t.surface.onBase)),
        if (custom) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: widget.onEdit,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.edit_outlined,
                  size: 13, color: t.surface.onBaseMuted),
            ),
          ),
        ],
      ],
    );
  }
}

/// The scene's colour as a small glowing dot.
class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
        ],
      ),
    );
  }
}

/// The active scene: a slowly-drifting gradient border in the scene's palette,
/// with a matching bloom. Reserved for the one active scene, so at most a
/// handful animate at once.
class _AuroraChip extends StatefulWidget {
  const _AuroraChip(
      {required this.palette, required this.onTap, required this.child});
  final _ScenePalette palette;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_AuroraChip> createState() => _AuroraChipState();
}

class _AuroraChipState extends State<_AuroraChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final colors = [...widget.palette.gradient, widget.palette.gradient.first];

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => Container(
          decoration: BoxDecoration(
            gradient: SweepGradient(
              colors: colors,
              transform: GradientRotation(_c.value * 6.2831853),
            ),
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: widget.palette.dot.withValues(alpha: 0.45),
                blurRadius: 18,
                spreadRadius: -4,
              ),
            ],
          ),
          padding: const EdgeInsets.all(1.6),
          child: child,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: t.surface.raised,
            borderRadius: BorderRadius.circular(9.6),
          ),
          padding: const EdgeInsets.fromLTRB(11, 8, 13, 8),
          child: widget.child,
        ),
      ),
    );
  }
}
