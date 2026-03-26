import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/scenes_provider.dart';
import '../../core/providers/devices_provider.dart';

class SceneEditorPage extends ConsumerStatefulWidget {
  final String? sceneId;
  const SceneEditorPage({this.sceneId, super.key});
  @override
  ConsumerState<SceneEditorPage> createState() => _SceneEditorPageState();
}

class _SceneEditorPageState extends ConsumerState<SceneEditorPage> {
  final _nameCtrl = TextEditingController();
  // Map of device_id → JSON text controller for state
  final Map<String, TextEditingController> _stateRows = {};
  bool _loading = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      if (widget.sceneId != null && widget.sceneId != 'new') {
        final scenes = ref.read(scenesProvider).valueOrNull ?? [];
        final matching =
            scenes.where((s) => s.id == widget.sceneId).toList();
        if (matching.isNotEmpty) {
          final scene = matching.first;
          _nameCtrl.text = scene.name;
          for (final e in scene.states.entries) {
            _stateRows[e.key] = TextEditingController(
                text: const JsonEncoder.withIndent('  ').convert(e.value));
          }
        }
      }
    }
  }

  void _addDevice(String deviceId) {
    if (_stateRows.containsKey(deviceId)) return;
    setState(() {
      _stateRows[deviceId] =
          TextEditingController(text: '{\n  "on": true\n}');
    });
  }

  Future<void> _save() async {
    if (_nameCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    try {
      final states = <String, dynamic>{};
      for (final e in _stateRows.entries) {
        try {
          states[e.key] = jsonDecode(e.value.text);
        } catch (_) {}
      }
      final payload = {'name': _nameCtrl.text, 'states': states};
      final api = ref.read(scenesApiProvider);
      if (widget.sceneId == null || widget.sceneId == 'new') {
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
  void dispose() {
    _nameCtrl.dispose();
    for (final c in _stateRows.values) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(devicesProvider);
    final deviceIds =
        devicesAsync.valueOrNull?.map((d) => d.id).toList() ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sceneId == null || widget.sceneId == 'new'
            ? 'New Scene'
            : 'Edit Scene'),
        actions: [
          if (!_loading)
            TextButton(
                onPressed: () => context.pop(),
                child: const Text('Cancel')),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)))
          else
            TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
              controller: _nameCtrl,
              decoration:
                  const InputDecoration(labelText: 'Scene name')),
          const SizedBox(height: 16),
          Row(children: [
            Text('Device states',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (deviceIds.isNotEmpty)
              DropdownButton<String>(
                hint: const Text('Add device'),
                items: deviceIds
                    .map((id) => DropdownMenuItem(
                        value: id,
                        child: Text(id,
                            overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (id) {
                  if (id != null) _addDevice(id);
                },
              ),
          ]),
          const SizedBox(height: 8),
          ..._stateRows.entries.map((e) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(e.key,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () =>
                              setState(() => _stateRows.remove(e.key)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ]),
                      TextFormField(
                        controller: e.value,
                        maxLines: null,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                        decoration:
                            const InputDecoration(border: InputBorder.none),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
