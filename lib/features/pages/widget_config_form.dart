import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/widget_registry.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/areas_provider.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/tokens.dart';
import '../../shell/hc_sheet.dart';

/// A widget's settings, built from the card's own [WidgetDescriptor.configFields].
///
/// The old CMS hand-wrote a bespoke form per card; this reads the same field
/// declarations the registry already carries, so every built-in AND every plugin
/// card gets a correct form for free. Returns the edited config, or null if
/// dismissed. It will not return a config the card's own `validate` rejects —
/// the same check core runs — so a bad card can't reach the save.
Future<Map<String, dynamic>?> showWidgetConfig(
  BuildContext context, {
  required WidgetDescriptor descriptor,
  required Map<String, dynamic> initial,
}) {
  return showHcSheet<Map<String, dynamic>>(
    context,
    title: descriptor.title,
    child: _ConfigSheet(descriptor: descriptor, initial: initial),
  );
}

/// The sheet host: header, the form, and Cancel/Done.
///
/// Buffers, because the sheet covers the card being edited — committing live
/// under an opaque panel would change something you cannot see. The inspector
/// is the opposite case and behaves the opposite way.
class _ConfigSheet extends StatefulWidget {
  const _ConfigSheet({required this.descriptor, required this.initial});

  final WidgetDescriptor descriptor;
  final Map<String, dynamic> initial;

  @override
  State<_ConfigSheet> createState() => _ConfigSheetState();
}

class _ConfigSheetState extends State<_ConfigSheet> {
  late Map<String, dynamic> _config = {...widget.initial};
  String? _error;

  void _save() {
    final message = widget.descriptor.validate?.call(_config);
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    Navigator.of(context).pop(_config);
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HcSheetHeader(title: 'Configure', subtitle: widget.descriptor.title),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(t.space.lg, 0, t.space.lg, t.space.md),
            child: WidgetConfigForm(
              descriptor: widget.descriptor,
              initial: widget.initial,
              onChanged: (c) => setState(() {
                _config = c;
                _error = null;
              }),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: t.space.lg),
            child: Text(_error!,
                style: t.text.bodySmallStyle.copyWith(color: t.accent.danger)),
          ),
        Padding(
          padding: EdgeInsets.all(t.space.lg),
          child: Row(
            children: [
              const Spacer(),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel')),
              SizedBox(width: t.space.xs),
              FilledButton(onPressed: _save, child: const Text('Done')),
            ],
          ),
        ),
      ],
    );
  }
}

/// A card's settings, with no chrome of its own.
///
/// Split out of the sheet so the inspector can host the same controls beside
/// the canvas. The two hosts differ in *when* an edit counts, which is the
/// whole reason they are different surfaces: the sheet buffers and commits on
/// Done because it covers the card you are editing, and the inspector applies
/// every change immediately because you can see the card while you make it.
class WidgetConfigForm extends ConsumerStatefulWidget {
  const WidgetConfigForm({
    super.key,
    required this.descriptor,
    required this.initial,
    required this.onChanged,
  });

  final WidgetDescriptor descriptor;
  final Map<String, dynamic> initial;

  /// Every edit, valid or not — the host decides what to do with an invalid
  /// one. Nothing is buffered here.
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  ConsumerState<WidgetConfigForm> createState() => _WidgetConfigFormState();
}

class _WidgetConfigFormState extends ConsumerState<WidgetConfigForm> {
  late final Map<String, dynamic> _config = {...widget.initial};
  String? _error;

  void _set(String name, Object? value) => setState(() {
        if (value == null) {
          _config.remove(name);
        } else {
          _config[name] = value;
        }
        widget.onChanged({..._config});
        _error = null;
      });

  /// The device-selection cluster shares one widget but only one of its three
  /// "how" fields applies at a time. Gate them on the chosen mode so the form
  /// shows the one field that matters, not all three.
  bool _visible(WidgetConfigField f) {
    final mode = _config['selection_mode'];
    if (mode == null) return true;
    return switch (f.name) {
      'device_ids' => mode == 'manual',
      'area_name' => mode == 'area',
      'query' => mode == 'query',
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final fields = widget.descriptor.configFields.where(_visible).toList();

    if (fields.isEmpty) {
      return Text('This widget has no options.',
          style: t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in fields)
          Padding(
            padding: EdgeInsets.only(bottom: t.space.md),
            child: _field(f),
          ),
        if (_error != null)
          Text(_error!,
              style: t.text.bodySmallStyle.copyWith(color: t.accent.danger)),
      ],
    );
  }

  /// The message the card's own validator gives, or null when it is happy.
  String? get validationError => widget.descriptor.validate?.call(_config);

  // -- field dispatch --------------------------------------------------------

  Widget _field(WidgetConfigField f) => switch (f.kind) {
        WidgetConfigKind.boolean => _boolean(f),
        WidgetConfigKind.choice => _choice(f),
        WidgetConfigKind.integer => _text(f, number: true),
        WidgetConfigKind.markdown => _text(f, lines: 5),
        WidgetConfigKind.url || WidgetConfigKind.text => _text(f),
        WidgetConfigKind.stringList => _stringList(f),
        WidgetConfigKind.areaName => _area(f),
        WidgetConfigKind.deviceRef => _deviceRef(f),
        WidgetConfigKind.deviceRefs => _deviceRefs(f),
        WidgetConfigKind.attribute => _attribute(f),
      };

  Widget _label(WidgetConfigField f) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.xs),
      child: Row(
        children: [
          Text(_title(f),
              style: t.text.bodySmallStyle.copyWith(
                  fontWeight: FontWeight.w600, color: t.surface.onBase)),
          if (f.required) Text(' *', style: TextStyle(color: t.accent.danger)),
        ],
      ),
    );
  }

  String _title(WidgetConfigField f) => f.label ?? humanize(f.name);

  Widget _help(WidgetConfigField f) {
    final t = HcTokens.of(context);
    if (f.help == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: t.space.xs),
      child: Text(f.help!,
          style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
    );
  }

  Widget _text(WidgetConfigField f, {bool number = false, int lines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        TextFormField(
          initialValue: '${_config[f.name] ?? ''}',
          keyboardType: number ? TextInputType.number : null,
          maxLines: lines,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: f.kind == WidgetConfigKind.url ? 'https://…' : null,
          ),
          onChanged: (v) {
            if (number) {
              _set(f.name, v.isEmpty ? null : int.tryParse(v));
            } else {
              _set(f.name, v.isEmpty ? null : v);
            }
          },
        ),
        _help(f),
      ],
    );
  }

  Widget _boolean(WidgetConfigField f) {
    final t = HcTokens.of(context);
    return Row(
      children: [
        Expanded(
            child: Text(_title(f),
                style: t.text.bodyStyle.copyWith(color: t.surface.onBase))),
        Switch(
          value: _config[f.name] == true,
          onChanged: (v) => _set(f.name, v),
        ),
      ],
    );
  }

  Widget _choice(WidgetConfigField f) {
    final options = f.options ?? const [];
    final value = _config[f.name] as String? ?? f.defaultValue as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        DropdownButtonFormField<String>(
          initialValue: options.contains(value) ? value : null,
          isExpanded: true,
          decoration: const InputDecoration(
              isDense: true, border: OutlineInputBorder()),
          items: [
            for (final o in options)
              DropdownMenuItem(value: o, child: Text(humanize(o))),
          ],
          onChanged: (v) => _set(f.name, v),
        ),
        _help(f),
      ],
    );
  }

  Widget _stringList(WidgetConfigField f) {
    final list =
        ((_config[f.name] as List?) ?? const []).map((e) => '$e').join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        TextFormField(
          initialValue: list,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            hintText: 'comma, separated, values',
          ),
          onChanged: (v) => _set(
            f.name,
            v
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
          ),
        ),
        _help(f),
      ],
    );
  }

  Widget _area(WidgetConfigField f) {
    final areasAsync = ref.watch(areasProvider);
    final devices = ref.watch(devicesProvider).value ?? const [];
    // The area catalog (GET /areas) is empty on a fresh system, so fall back to
    // the areas devices actually report. Matching on the device's effective
    // area is also what the widget filters on, so a device-derived name is
    // guaranteed to select something — a catalog-only name might not.
    final names = <String>{
      for (final a in (areasAsync.value ?? const []))
        (a['name'] ?? a['id'] ?? '').toString(),
      for (final d in devices)
        if ((d.effectiveArea ?? '').isNotEmpty) d.effectiveArea!,
    }.where((s) => s.isNotEmpty).toList()
      ..sort();
    final value = _config[f.name] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        if (names.isEmpty)
          _hint(areasAsync.isLoading
              ? 'Loading areas…'
              : 'No areas yet. Assign devices to rooms in Manage, or pick '
                  'Manual/Query instead.')
        else
          DropdownButtonFormField<String>(
            initialValue: names.contains(value) ? value : null,
            isExpanded: true,
            decoration: const InputDecoration(
                isDense: true, border: OutlineInputBorder()),
            items: [
              for (final n in names)
                DropdownMenuItem(value: n, child: Text(humanize(n))),
            ],
            onChanged: (v) => _set(f.name, v),
          ),
        _help(f),
      ],
    );
  }

  // A quiet inline note where a control would be, for the empty/loading states
  // that an unselectable dropdown used to hide.
  Widget _hint(String message) {
    final t = HcTokens.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: t.radius.smR,
        border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
      ),
      child: Text(message,
          style: t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted)),
    );
  }

  Widget _deviceRef(WidgetConfigField f) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value ?? const [];
    final id = _config[f.name] as String?;
    final selected = devices.where((d) => d.id == id).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        OutlinedButton(
          onPressed: () async {
            final picked = await _pickDevices(context, devices,
                single: true, selected: {if (id != null) id});
            if (picked != null) {
              _set(f.name, picked.isEmpty ? null : picked.first);
            }
          },
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(selected?.displayName ?? 'Choose a device…',
                style: TextStyle(
                    color: selected == null
                        ? t.surface.onBaseMuted
                        : t.surface.onBase)),
          ),
        ),
        _help(f),
      ],
    );
  }

  Widget _deviceRefs(WidgetConfigField f) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value ?? const [];
    final ids =
        ((_config[f.name] as List?) ?? const []).map((e) => '$e').toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        OutlinedButton(
          onPressed: () async {
            final picked = await _pickDevices(context, devices,
                single: false, selected: ids);
            if (picked != null) _set(f.name, picked);
          },
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              ids.isEmpty ? 'Choose devices…' : '${ids.length} selected',
              style: TextStyle(
                  color:
                      ids.isEmpty ? t.surface.onBaseMuted : t.surface.onBase),
            ),
          ),
        ),
      ],
    );
  }

  Widget _attribute(WidgetConfigField f) {
    // Attributes come from whichever device this widget points at.
    final devices = ref.watch(devicesProvider).value ?? const [];
    final deviceId = _config['device_id'] as String?;
    final device = devices.where((d) => d.id == deviceId).firstOrNull;
    final attrs = <String>{
      ...?device?.state.keys,
      ...?device?.schema?.attributes.keys,
    }.toList()
      ..sort();
    final value = _config[f.name] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        DropdownButtonFormField<String>(
          initialValue: attrs.contains(value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: device == null ? 'Pick a device first' : null,
          ),
          items: [
            for (final a in attrs)
              DropdownMenuItem(value: a, child: Text(humanize(a))),
          ],
          onChanged: (v) => _set(f.name, v),
        ),
      ],
    );
  }
}

/// A searchable device picker, single or multi. Returns the chosen ids, or null
/// if dismissed. 167 devices is too many for a dropdown, so this searches.
Future<List<String>?> _pickDevices(
    BuildContext context, List<DeviceState> devices,
    {required bool single, required Set<String> selected}) {
  return showHcSheet<List<String>>(
    context,
    title: 'Pick devices',
    child: _DevicePicker(devices: devices, single: single, initial: selected),
  );
}

class _DevicePicker extends StatefulWidget {
  const _DevicePicker(
      {required this.devices, required this.single, required this.initial});

  final List<DeviceState> devices;
  final bool single;
  final Set<String> initial;

  @override
  State<_DevicePicker> createState() => _DevicePickerState();
}

class _DevicePickerState extends State<_DevicePicker> {
  late final Set<String> _selected = {...widget.initial};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final q = _query.toLowerCase();
    final matches = widget.devices
        .where((d) =>
            q.isEmpty ||
            d.displayName.toLowerCase().contains(q) ||
            (d.effectiveArea ?? '').toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HcSheetHeader(title: 'Pick devices'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space.lg),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search devices',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SizedBox(height: t.space.sm),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.symmetric(horizontal: t.space.md),
            itemCount: matches.length,
            itemBuilder: (context, i) {
              final d = matches[i];
              final on = _selected.contains(d.id);
              return CheckboxListTile(
                dense: true,
                value: on,
                title: Text(d.displayName,
                    style: t.text.bodyStyle.copyWith(color: t.surface.onBase)),
                subtitle: (d.effectiveArea ?? '').isEmpty
                    ? null
                    : Text(humanize(d.effectiveArea!),
                        style: t.text.captionStyle
                            .copyWith(color: t.surface.onBaseMuted)),
                onChanged: (_) => setState(() {
                  if (widget.single) {
                    _selected
                      ..clear()
                      ..add(d.id);
                    Navigator.of(context).pop(_selected.toList());
                    return;
                  }
                  on ? _selected.remove(d.id) : _selected.add(d.id);
                }),
              );
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.all(t.space.lg),
          child: Row(
            children: [
              const Spacer(),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel')),
              SizedBox(width: t.space.xs),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_selected.toList()),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
