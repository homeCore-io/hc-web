import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/scenes_provider.dart';
import '../../core/providers/devices_provider.dart';

// ---------------------------------------------------------------------------
// Device state entry — the structured representation we edit
// ---------------------------------------------------------------------------

class _DeviceEntry {
  final String deviceId;
  final String displayName;

  /// Mutable attribute map for editing
  final Map<String, dynamic> attrs;

  _DeviceEntry({
    required this.deviceId,
    required this.displayName,
    required this.attrs,
  });
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class SceneEditorPage extends ConsumerStatefulWidget {
  final String? sceneId;
  const SceneEditorPage({this.sceneId, super.key});

  @override
  ConsumerState<SceneEditorPage> createState() => _SceneEditorPageState();
}

class _SceneEditorPageState extends ConsumerState<SceneEditorPage> {
  final _nameCtrl = TextEditingController();
  final List<_DeviceEntry> _entries = [];
  bool _loading = false;
  bool _initialized = false;
  String? _selectedDeviceId; // tracks which entry is "focused" on mobile

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    if (widget.sceneId != null && widget.sceneId != 'new') {
      final scenes = ref.read(scenesProvider).valueOrNull ?? [];
      final match = scenes.where((s) => s.id == widget.sceneId).toList();
      if (match.isNotEmpty) {
        final scene = match.first;
        _nameCtrl.text = scene.name;
        final devices = ref.read(devicesProvider).valueOrNull ?? [];
        for (final e in scene.states.entries) {
          final dev = devices.firstWhere((d) => d.id == e.key,
              orElse: () => DeviceState(
                    id: e.key,
                    pluginId: '',
                    available: false,
                    state: {},
                  ));
          _entries.add(_DeviceEntry(
            deviceId: e.key,
            displayName: dev.displayName,
            attrs: Map<String, dynamic>.from(
                e.value is Map ? (e.value as Map).cast<String, dynamic>() : {}),
          ));
        }
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _isNew => widget.sceneId == null || widget.sceneId == 'new';

  void _addDevice(DeviceState device) {
    if (_entries.any((e) => e.deviceId == device.id)) return;
    // Seed with the device's current state attributes, defaulting to on:true
    final seed = Map<String, dynamic>.from(device.state);
    if (seed.isEmpty) seed['on'] = true;
    setState(() {
      _entries.add(_DeviceEntry(
        deviceId: device.id,
        displayName: device.displayName,
        attrs: seed,
      ));
      _selectedDeviceId = device.id;
    });
  }

  void _removeDevice(String deviceId) {
    setState(() {
      _entries.removeWhere((e) => e.deviceId == deviceId);
      if (_selectedDeviceId == deviceId) _selectedDeviceId = null;
    });
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final states = {for (final e in _entries) e.deviceId: e.attrs};
      final payload = {'name': _nameCtrl.text.trim(), 'states': states};
      final api = ref.read(scenesApiProvider);
      if (_isNew) {
        await api.createScene(payload);
      } else {
        await api.updateScene(widget.sceneId!, payload);
      }
      ref.invalidate(scenesProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(devicesProvider);
    final allDevices = devicesAsync.valueOrNull ?? [];
    // Exclude plugin scenes and already-added devices
    final addableDevices = allDevices
        .where((d) =>
            d.deviceType != 'scene' && !_entries.any((e) => e.deviceId == d.id))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New Scene' : 'Edit Scene'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            TextButton(
                onPressed: () => context.pop(), child: const Text('Cancel')),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        return wide
            ? _WideLayout(
                nameCtrl: _nameCtrl,
                entries: _entries,
                addableDevices: addableDevices,
                onAdd: _addDevice,
                onRemove: _removeDevice,
                onAttrChanged: (_) => setState(() {}),
              )
            : _NarrowLayout(
                nameCtrl: _nameCtrl,
                entries: _entries,
                addableDevices: addableDevices,
                selectedId: _selectedDeviceId,
                onSelectDevice: (id) => setState(() => _selectedDeviceId = id),
                onAdd: _addDevice,
                onRemove: _removeDevice,
                onAttrChanged: (_) => setState(() {}),
              );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Wide layout: two columns side-by-side
// ---------------------------------------------------------------------------

class _WideLayout extends StatelessWidget {
  final TextEditingController nameCtrl;
  final List<_DeviceEntry> entries;
  final List<DeviceState> addableDevices;
  final void Function(DeviceState) onAdd;
  final void Function(String) onRemove;
  final void Function(String) onAttrChanged;

  const _WideLayout({
    required this.nameCtrl,
    required this.entries,
    required this.addableDevices,
    required this.onAdd,
    required this.onRemove,
    required this.onAttrChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Scene name at top
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextFormField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Scene name',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const Divider(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: device picker
              SizedBox(
                width: 280,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text('Add devices',
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    Expanded(
                      child: _DevicePickerList(
                        devices: addableDevices,
                        onAdd: onAdd,
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              // Right: state editors for scene entries
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        'Scene devices (${entries.length})',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Expanded(
                      child: entries.isEmpty
                          ? const Center(
                              child: Text('← Add devices from the list',
                                  textAlign: TextAlign.center))
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: entries.length,
                              itemBuilder: (_, i) => _DeviceStateCard(
                                entry: entries[i],
                                onRemove: onRemove,
                                onChanged: onAttrChanged,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Narrow layout: tabs
// ---------------------------------------------------------------------------

class _NarrowLayout extends StatelessWidget {
  final TextEditingController nameCtrl;
  final List<_DeviceEntry> entries;
  final List<DeviceState> addableDevices;
  final String? selectedId;
  final void Function(String?) onSelectDevice;
  final void Function(DeviceState) onAdd;
  final void Function(String) onRemove;
  final void Function(String) onAttrChanged;

  const _NarrowLayout({
    required this.nameCtrl,
    required this.entries,
    required this.addableDevices,
    required this.selectedId,
    required this.onSelectDevice,
    required this.onAdd,
    required this.onRemove,
    required this.onAttrChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextFormField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Scene name', border: OutlineInputBorder()),
            ),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Add Devices'),
              Tab(text: 'Scene Devices'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _DevicePickerList(devices: addableDevices, onAdd: onAdd),
                entries.isEmpty
                    ? const Center(
                        child: Text('No devices added yet.',
                            textAlign: TextAlign.center))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: entries.length,
                        itemBuilder: (_, i) => _DeviceStateCard(
                          entry: entries[i],
                          onRemove: onRemove,
                          onChanged: onAttrChanged,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Device picker list (left panel) — grouped by area
// ---------------------------------------------------------------------------

class _DevicePickerList extends StatefulWidget {
  final List<DeviceState> devices;
  final void Function(DeviceState) onAdd;
  const _DevicePickerList({required this.devices, required this.onAdd});

  @override
  State<_DevicePickerList> createState() => _DevicePickerListState();
}

class _DevicePickerListState extends State<_DevicePickerList> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
        () => setState(() => _query = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.devices
        : widget.devices
            .where((d) =>
                d.displayName.toLowerCase().contains(_query) ||
                (d.effectiveArea ?? '').toLowerCase().contains(_query))
            .toList();

    // Group by area
    final Map<String, List<DeviceState>> byArea = {};
    for (final d in filtered) {
      final area = d.effectiveArea ?? 'Unassigned';
      byArea.putIfAbsent(area, () => []).add(d);
    }
    final areas = byArea.keys.toList()..sort();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Search devices…',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No devices found'))
              : ListView(
                  children: [
                    for (final area in areas) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: Text(
                          area,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ),
                      for (final device in byArea[area]!)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.devices, size: 18),
                          title: Text(device.displayName,
                              style: Theme.of(context).textTheme.bodySmall),
                          trailing: IconButton(
                            icon:
                                const Icon(Icons.add_circle_outline, size: 18),
                            onPressed: () => widget.onAdd(device),
                            tooltip: 'Add to scene',
                          ),
                          onTap: () => widget.onAdd(device),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Device state card (right panel) — smart controls per attribute type
// ---------------------------------------------------------------------------

class _DeviceStateCard extends StatefulWidget {
  final _DeviceEntry entry;
  final void Function(String deviceId) onRemove;
  final void Function(String deviceId) onChanged;

  const _DeviceStateCard({
    required this.entry,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  State<_DeviceStateCard> createState() => _DeviceStateCardState();
}

class _DeviceStateCardState extends State<_DeviceStateCard> {
  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: device name + remove button
            Row(
              children: [
                const Icon(Icons.devices, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(entry.displayName,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  onPressed: () => widget.onRemove(entry.deviceId),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Remove from scene',
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Attribute controls
            ...entry.attrs.entries.map((e) => _AttrControl(
                  attrKey: e.key,
                  value: e.value,
                  onChanged: (newVal) {
                    setState(() {
                      entry.attrs[e.key] = newVal;
                    });
                    widget.onChanged(entry.deviceId);
                  },
                )),
            // Add attribute button
            TextButton.icon(
              onPressed: () => _addAttr(context, entry),
              icon: const Icon(Icons.add, size: 14),
              label:
                  const Text('Add attribute', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addAttr(BuildContext context, _DeviceEntry entry) async {
    final keyCtrl = TextEditingController();
    final valCtrl = TextEditingController(text: 'true');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add attribute'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: keyCtrl,
                decoration: const InputDecoration(labelText: 'Attribute name')),
            const SizedBox(height: 8),
            TextField(
                controller: valCtrl,
                decoration: const InputDecoration(labelText: 'Value (JSON)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (result == true && keyCtrl.text.isNotEmpty) {
      dynamic parsed;
      try {
        // Simple value parsing
        final v = valCtrl.text.trim();
        if (v == 'true') {
          parsed = true;
        } else if (v == 'false') {
          parsed = false;
        } else if (int.tryParse(v) != null) {
          parsed = int.parse(v);
        } else if (double.tryParse(v) != null) {
          parsed = double.parse(v);
        } else {
          parsed = v;
        }
      } catch (_) {
        parsed = valCtrl.text.trim();
      }
      setState(() {
        entry.attrs[keyCtrl.text.trim()] = parsed;
      });
      widget.onChanged(entry.deviceId);
    }
  }
}

// ---------------------------------------------------------------------------
// Single attribute control — type-adaptive
// ---------------------------------------------------------------------------

class _AttrControl extends StatelessWidget {
  final String attrKey;
  final dynamic value;
  final void Function(dynamic) onChanged;

  const _AttrControl({
    required this.attrKey,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (value is bool) {
      return _BoolControl(
          label: attrKey, value: value as bool, onChanged: onChanged);
    }
    if (attrKey == 'brightness' && value is num) {
      return _SliderControl(
          label: 'Brightness',
          value: (value as num).toDouble(),
          min: 0,
          max: 255,
          divisions: 255,
          onChanged: (v) => onChanged(v.round()));
    }
    if (attrKey == 'color_temp' && value is num) {
      return _SliderControl(
          label: 'Color temp (K)',
          value: (value as num).toDouble(),
          min: 2700,
          max: 6500,
          divisions: 76,
          onChanged: (v) => onChanged(v.round()));
    }
    if (value is num) {
      return _NumberControl(
          label: attrKey, value: value as num, onChanged: onChanged);
    }
    // Fallback: text field
    return _TextControl(
        label: attrKey, value: value.toString(), onChanged: onChanged);
  }
}

class _BoolControl extends StatelessWidget {
  final String label;
  final bool value;
  final void Function(bool) onChanged;
  const _BoolControl(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: Theme.of(context).textTheme.bodySmall),
        value: value,
        onChanged: onChanged,
      );
}

class _SliderControl extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final void Function(double) onChanged;

  const _SliderControl({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            Text(value.round().toString(),
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _NumberControl extends StatefulWidget {
  final String label;
  final num value;
  final void Function(num) onChanged;
  const _NumberControl(
      {required this.label, required this.value, required this.onChanged});

  @override
  State<_NumberControl> createState() => _NumberControlState();
}

class _NumberControlState extends State<_NumberControl> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toString());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: _ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
            labelText: widget.label,
            isDense: true,
            border: const OutlineInputBorder()),
        onChanged: (v) {
          final n = num.tryParse(v);
          if (n != null) widget.onChanged(n);
        },
      );
}

class _TextControl extends StatefulWidget {
  final String label;
  final String value;
  final void Function(String) onChanged;
  const _TextControl(
      {required this.label, required this.value, required this.onChanged});

  @override
  State<_TextControl> createState() => _TextControlState();
}

class _TextControlState extends State<_TextControl> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: _ctrl,
        decoration: InputDecoration(
            labelText: widget.label,
            isDense: true,
            border: const OutlineInputBorder()),
        onChanged: widget.onChanged,
      );
}
