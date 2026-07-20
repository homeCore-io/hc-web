import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/text/humanize.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

class DeviceDetailPage extends ConsumerWidget {
  final String deviceId;
  const DeviceDetailPage({required this.deviceId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesProvider);

    return devicesAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (devices) {
        final device = devices.where((d) => d.id == deviceId).firstOrNull;
        if (device == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Device')),
            body: const Center(child: Text('Device not found')),
          );
        }
        return _DeviceDetailView(device: device);
      },
    );
  }
}

// ── Main view ─────────────────────────────────────────────────────────────────

class _DeviceDetailView extends ConsumerWidget {
  final DeviceState device;
  const _DeviceDetailView({required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(device.displayName),
        actions: [
          // availability chip
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Chip(
              avatar: Icon(
                device.available ? Icons.circle : Icons.circle_outlined,
                color: device.available ? Colors.green : Colors.red,
                size: 12,
              ),
              label: Text(device.available ? 'online' : 'offline'),
              visualDensity: VisualDensity.compact,
            ),
          ),
          // edit
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit device',
            onPressed: () => _showEditDialog(context, ref),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Info card ──────────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Device Info',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _InfoRow(label: 'Device ID', value: device.id),
                  if (device.canonicalName != null &&
                      device.canonicalName!.isNotEmpty)
                    _InfoRow(label: 'Canonical', value: device.canonicalName!),
                  _InfoRow(label: 'Plugin', value: device.pluginId),
                  _InfoRow(
                      label: 'Area',
                      value:
                          device.effectiveArea != null ? humanize(device.effectiveArea!) : '—'),
                  if (device.deviceType != null)
                    _InfoRow(
                        label: 'Type', value: humanize(device.deviceType!)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (device.isMediaPlayer) ...[
            _MediaPlayerCard(device: device),
            const SizedBox(height: 16),
            _MediaPlayerAdvancedCard(device: device),
            const SizedBox(height: 16),
          ],

          // ── Controls card ──────────────────────────────────────────────────
          Text(
            device.isMediaPlayer ? 'Raw State' : 'Controls',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ..._visibleAttributeEntries(device).map((entry) => _AttributeControl(
                deviceId: device.id,
                attribute: entry.key,
                value: entry.value,
              )),
          if (_visibleAttributeEntries(device).isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                device.isMediaPlayer
                    ? 'No additional raw attributes'
                    : 'No controllable attributes',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          const SizedBox(height: 24),

          // ── Navigation ─────────────────────────────────────────────────────
          OutlinedButton.icon(
            icon: const Icon(Icons.history),
            label: const Text('View History'),
            onPressed: () => context.push('/devices/${device.id}/history'),
          ),
          const SizedBox(height: 32),

          // ── Danger zone ────────────────────────────────────────────────────
          const Divider(),
          const SizedBox(height: 8),
          Text('Danger Zone',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 4),
          Text(
            'Deleting a device removes it from the store and nullifies '
            'any rule references to it. This cannot be undone.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.error),
            label: Text('Delete Device',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
            onPressed: () => _confirmDelete(context, ref),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Edit dialog ─────────────────────────────────────────────────────────────

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref) async {
    // Collect existing area names from the devices list for autocomplete
    final allDevices = ref.read(devicesProvider).valueOrNull ?? [];
    final existingAreas = allDevices
        .map((d) => d.area)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();

    await showDialog<void>(
      context: context,
      builder: (_) => _EditDeviceDialog(
        device: device,
        existingAreas: existingAreas,
        onSave: (name, area) async {
          final body = <String, dynamic>{};
          if (name != device.displayName) body['name'] = name;
          // area: send null explicitly to clear, or new string to set
          if (area != device.effectiveArea) {
            body['area'] = area; // null or string
          }
          if (body.isEmpty) return;
          await ref
              .read(devicesProvider.notifier)
              .updateDevice(device.id, body);
        },
      ),
    );
  }

  // ── Delete confirmation ─────────────────────────────────────────────────────

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete device?'),
        content: Text(
          'This will permanently remove "${device.displayName}" and '
          'nullify its references in all rule files.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    await ref.read(devicesProvider.notifier).deleteDevice(device.id);

    if (context.mounted) context.pop();
  }
}

Iterable<MapEntry<String, dynamic>> _visibleAttributeEntries(
    DeviceState device) {
  const mediaKeys = {
    'title',
    'artist',
    'album',
    'source',
    'state',
    'position_secs',
    'duration_secs',
    'media_title',
    'media_artist',
    'media_album',
    'media_position',
    'media_duration',
    'supported_actions',
    'ui_enrichments',
    'sonos',
  };
  if (!device.isMediaPlayer) return device.state.entries;
  return device.state.entries.where((entry) => !mediaKeys.contains(entry.key));
}

// ── Edit dialog widget ────────────────────────────────────────────────────────

class _EditDeviceDialog extends StatefulWidget {
  final DeviceState device;
  final List<String> existingAreas;
  final Future<void> Function(String name, String? area) onSave;

  const _EditDeviceDialog({
    required this.device,
    required this.existingAreas,
    required this.onSave,
  });

  @override
  State<_EditDeviceDialog> createState() => _EditDeviceDialogState();
}

class _EditDeviceDialogState extends State<_EditDeviceDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _areaCtrl;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.device.displayName);
    _areaCtrl = TextEditingController(text: widget.device.effectiveArea ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _areaCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name cannot be empty');
      return;
    }
    final areaText = _areaCtrl.text.trim();
    final area = areaText.isEmpty ? null : areaText;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(name, area);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Device'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Name field
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            // Area field with autocomplete from existing areas
            Autocomplete<String>(
              initialValue: TextEditingValue(text: widget.device.effectiveArea ?? ''),
              optionsBuilder: (value) {
                if (value.text.isEmpty) return widget.existingAreas;
                final q = value.text.toLowerCase();
                return widget.existingAreas
                    .where((a) => a.toLowerCase().contains(q));
              },
              fieldViewBuilder: (ctx, ctrl, focusNode, onSubmit) {
                // Keep _areaCtrl in sync with the autocomplete's internal controller
                ctrl.addListener(() => _areaCtrl.text = ctrl.text);
                return TextFormField(
                  controller: ctrl,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'Area',
                    hintText: 'Leave blank to clear',
                    border: const OutlineInputBorder(),
                    suffixIcon: ctrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              ctrl.clear();
                              _areaCtrl.clear();
                            })
                        : null,
                  ),
                  onFieldSubmitted: (_) => onSubmit(),
                );
              },
              onSelected: (value) => _areaCtrl.text = value,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 90,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(
              child:
                  Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _MediaPlayerCard extends ConsumerStatefulWidget {
  final DeviceState device;
  const _MediaPlayerCard({required this.device});

  @override
  ConsumerState<_MediaPlayerCard> createState() => _MediaPlayerCardState();
}

class _MediaPlayerCardState extends ConsumerState<_MediaPlayerCard> {
  bool _busy = false;
  double? _volumeDraft;

  Future<void> _send(Map<String, dynamic> body) async {
    setState(() => _busy = true);
    try {
      await ref.read(devicesApiProvider).setDeviceState(widget.device.id, body);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final progress = (device.durationSecs != null && device.durationSecs! > 0)
        ? ((device.positionSecs ?? 0) / device.durationSecs!).clamp(0.0, 1.0)
        : null;
    final stateLabel = device.playbackState[0].toUpperCase() +
        device.playbackState.substring(1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Media Player',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (_busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(stateLabel)),
                if (device.source != null && device.source!.isNotEmpty)
                  Chip(label: Text(device.source!)),
                if (device.muted == true) const Chip(label: Text('Muted')),
              ],
            ),
            if (device.title != null ||
                device.artist != null ||
                device.album != null) ...[
              const SizedBox(height: 12),
              if (device.title != null)
                Text(device.title!,
                    style: Theme.of(context).textTheme.titleMedium),
              if (device.artist != null)
                Text(device.artist!,
                    style: Theme.of(context).textTheme.bodyMedium),
              if (device.album != null)
                Text(device.album!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.65),
                        )),
            ],
            if (progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 6),
              Text(
                '${_formatDuration(device.positionSecs)} / ${_formatDuration(device.durationSecs)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (device.supportsAction('previous'))
                  OutlinedButton.icon(
                    onPressed:
                        _busy ? null : () => _send({'action': 'previous'}),
                    icon: const Icon(Icons.skip_previous),
                    label: const Text('Previous'),
                  ),
                if (device.supportsAction('play'))
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _send({'action': 'play'}),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play'),
                  ),
                if (device.supportsAction('pause'))
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _send({'action': 'pause'}),
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  ),
                if (device.supportsAction('stop'))
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _send({'action': 'stop'}),
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                if (device.supportsAction('next'))
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _send({'action': 'next'}),
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Next'),
                  ),
              ],
            ),
            if (device.supportsAction('set_volume') ||
                device.supportsAction('set_mute')) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  if (device.supportsAction('set_mute'))
                    IconButton(
                      onPressed: _busy || device.muted == null
                          ? null
                          : () => _send({
                                'action': 'set_mute',
                                'muted': !(device.muted ?? false),
                              }),
                      icon: Icon(
                        device.muted == true
                            ? Icons.volume_off
                            : Icons.volume_up,
                      ),
                    ),
                  Expanded(
                    child: Slider(
                      value: (_volumeDraft ?? device.volumePercent ?? 0)
                          .toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 100,
                      label:
                          '${(_volumeDraft ?? device.volumePercent ?? 0).round()}%',
                      onChanged: device.supportsAction('set_volume') && !_busy
                          ? (value) => setState(() => _volumeDraft = value)
                          : null,
                      onChangeEnd: device.supportsAction('set_volume') && !_busy
                          ? (value) async {
                              await _send({
                                'action': 'set_volume',
                                'volume': value.round(),
                              });
                              if (mounted) setState(() => _volumeDraft = null);
                            }
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${(_volumeDraft ?? device.volumePercent ?? 0).round()}%',
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MediaPlayerAdvancedCard extends ConsumerStatefulWidget {
  final DeviceState device;
  const _MediaPlayerAdvancedCard({required this.device});

  @override
  ConsumerState<_MediaPlayerAdvancedCard> createState() =>
      _MediaPlayerAdvancedCardState();
}

class _MediaPlayerAdvancedCardState
    extends ConsumerState<_MediaPlayerAdvancedCard> {
  bool _busy = false;
  String? _selectedFavorite;
  String? _selectedPlaylist;

  Future<void> _send(Map<String, dynamic> body) async {
    setState(() => _busy = true);
    try {
      await ref.read(devicesApiProvider).setDeviceState(widget.device.id, body);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final sonos = device.sonos;
    final favorites =
        ((sonos['favorites'] ?? device.state['available_favorites']) as List? ??
                const [])
            .whereType<String>()
            .toList();
    final playlists =
        ((sonos['playlists'] ?? device.state['available_playlists']) as List? ??
                const [])
            .whereType<String>()
            .toList();
    final coordinator =
        sonos['group_coordinator'] ?? device.state['group_coordinator'];
    final members =
        ((sonos['group_members'] ?? device.state['group_members']) as List? ??
                const [])
            .whereType<String>()
            .toList();

    if (favorites.isEmpty &&
        playlists.isEmpty &&
        coordinator == null &&
        members.isEmpty &&
        device.uiEnrichments.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Plugin Enrichments',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (_busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (device.uiEnrichments.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: device.uiEnrichments
                    .map((item) => Chip(label: Text(item)))
                    .toList(),
              ),
            if (coordinator != null || members.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (coordinator != null)
                _InfoRow(label: 'Coordinator', value: coordinator.toString()),
              if (members.isNotEmpty)
                _InfoRow(label: 'Group', value: members.join(', ')),
            ],
            if (favorites.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Favorites', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: favorites.contains(_selectedFavorite)
                          ? _selectedFavorite
                          : null,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      hint: const Text('Choose favorite'),
                      items: favorites
                          .map((item) =>
                              DropdownMenuItem(value: item, child: Text(item)))
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (value) =>
                              setState(() => _selectedFavorite = value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy || _selectedFavorite == null
                        ? null
                        : () => _send({
                              'action': 'play_media',
                              'media_type': 'favorite',
                              'name': _selectedFavorite,
                            }),
                    child: const Text('Play'),
                  ),
                ],
              ),
            ],
            if (playlists.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Playlists', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: playlists.contains(_selectedPlaylist)
                          ? _selectedPlaylist
                          : null,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      hint: const Text('Choose playlist'),
                      items: playlists
                          .map((item) =>
                              DropdownMenuItem(value: item, child: Text(item)))
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (value) =>
                              setState(() => _selectedPlaylist = value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy || _selectedPlaylist == null
                        ? null
                        : () => _send({
                              'action': 'play_media',
                              'media_type': 'playlist',
                              'name': _selectedPlaylist,
                            }),
                    child: const Text('Play'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatDuration(int? secs) {
  if (secs == null) return '0:00';
  final minutes = secs ~/ 60;
  final seconds = secs % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

// ── Attribute control ─────────────────────────────────────────────────────────

class _AttributeControl extends ConsumerStatefulWidget {
  final String deviceId;
  final String attribute;
  final dynamic value;
  const _AttributeControl(
      {required this.deviceId, required this.attribute, required this.value});

  @override
  ConsumerState<_AttributeControl> createState() => _AttributeControlState();
}

class _AttributeControlState extends ConsumerState<_AttributeControl> {
  bool _busy = false;

  Future<void> _send(dynamic newValue) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(devicesApiProvider)
          .setDeviceState(widget.deviceId, {widget.attribute: newValue});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final label = widget.attribute.replaceAll('_', ' ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            _busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : _buildControl(v),
          ],
        ),
      ),
    );
  }

  Widget _buildControl(dynamic v) {
    if (v is bool) {
      return Switch(value: v, onChanged: _send);
    }
    if (v is num) {
      final max = v <= 100 ? 100.0 : 255.0;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(v.toString()),
          SizedBox(
            width: 150,
            child: Slider(
              value: v.toDouble().clamp(0, max),
              min: 0,
              max: max,
              divisions: max.toInt(),
              onChangeEnd: (val) => _send(val.round()),
              onChanged: (_) {},
            ),
          ),
        ],
      );
    }
    return Text(v?.toString() ?? 'null',
        style: Theme.of(context).textTheme.bodyMedium);
  }
}
