import 'package:flutter/material.dart';

import '../../core/schema/plugin_capabilities.dart';

/// A form generated from an action's `params` manifest.
///
/// No plugin is named anywhere in this file. Ecowitt's nine-parameter
/// `set_custom_server` — with enums, integer ranges, defaults and optional
/// strings — renders here purely from what the plugin declared, and so will the
/// next plugin's action that nobody has written yet.
class ActionForm extends StatefulWidget {
  const ActionForm({
    super.key,
    required this.action,
    required this.onSubmit,
  });

  final PluginAction action;
  final void Function(Map<String, Object?> params) onSubmit;

  @override
  State<ActionForm> createState() => _ActionFormState();
}

class _ActionFormState extends State<ActionForm> {
  late final Map<String, Object?> _values = {
    // Seed declared defaults so the form submits sensibly untouched — most of
    // these actions are meant to be run with one click.
    for (final p in widget.action.params)
      if (p.defaultValue != null) p.name: p.defaultValue,
  };

  String? _missing;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;

    return AlertDialog(
      title: Text(action.label),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (action.description != null) ...[
                Text(
                  action.description!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
              ],
              if (action.params.isEmpty)
                Text(
                  'This action takes no parameters.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              for (final p in action.params)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _param(p),
                ),
              if (_missing != null)
                Text(
                  '$_missing is required.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (action.stream) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.stream, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        action.cancelable
                            ? 'Reports progress live, and can be cancelled.'
                            : 'Reports progress live.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(action.stream ? 'Start' : 'Run'),
        ),
      ],
    );
  }

  void _submit() {
    for (final p in widget.action.params) {
      if (p.required && _values[p.name] == null) {
        setState(() => _missing = p.name);
        return;
      }
    }
    // Omit blanks rather than sending nulls: these params are optional on the
    // plugin side and several of them mean "fall back to the configured value"
    // when absent.
    widget.onSubmit({
      for (final e in _values.entries)
        if (e.value != null && e.value != '') e.key: e.value,
    });
  }

  Widget _param(ParamSpec p) {
    final label = p.required ? p.name : '${p.name} (optional)';

    if (p.options case final options?) {
      return DropdownButtonFormField<String>(
        initialValue: _values[p.name] as String?,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: p.description,
          helperMaxLines: 3,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
        ],
        onChanged: (v) => setState(() => _values[p.name] = v),
      );
    }

    return switch (p.type) {
      'boolean' => SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _values[p.name] == true,
          title: Text(label),
          subtitle: p.description == null ? null : Text(p.description!),
          onChanged: (v) => setState(() => _values[p.name] = v),
        ),
      'integer' || 'number' => TextFormField(
          initialValue: _values[p.name]?.toString() ?? '',
          decoration: InputDecoration(
            labelText: label,
            // Surface the declared bounds — core and the plugin enforce them,
            // so the user should not have to discover them by being rejected.
            helperText: [
              if (p.description != null) p.description!,
              if (p.hasRange) '${p.minimum}–${p.maximum}',
            ].join(' · '),
            helperMaxLines: 3,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          onChanged: (v) => setState(() {
            _values[p.name] = v.isEmpty
                ? null
                : (p.type == 'integer' ? int.tryParse(v) : num.tryParse(v));
          }),
        ),
      _ => TextFormField(
          initialValue: _values[p.name]?.toString() ?? '',
          decoration: InputDecoration(
            labelText: label,
            helperText: p.description,
            helperMaxLines: 3,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _values[p.name] = v),
        ),
    };
  }
}
