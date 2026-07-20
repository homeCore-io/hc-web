import 'package:flutter/material.dart';

import '../../core/schema/plugin_capabilities.dart';
import '../../core/text/humanize.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/tokens.dart';

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

    final t = HcTokens.of(context);

    return HcDialog(
      title: action.label,
      description: action.description,
      width: 520,
      actions: [
        HcButton(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        HcButton(
          label: action.stream ? 'Start' : 'Run',
          kind: HcButtonKind.primary,
          onPressed: _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (action.params.isEmpty)
            Text(
              'This action takes no parameters.',
              style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted),
            ),
          for (final p in action.params)
            Padding(
              padding: EdgeInsets.only(bottom: t.space.md),
              child: _param(p),
            ),
          if (_missing != null)
            Text(
              '${humanize(_missing!)} is required.',
              style: TextStyle(fontSize: 12.5, color: t.accent.danger),
            ),
          if (action.stream) ...[
            SizedBox(height: t.space.sm),
            Row(
              children: [
                Icon(Icons.stream, size: 14, color: t.surface.onBaseMuted),
                SizedBox(width: t.space.sm),
                Expanded(
                  child: Text(
                    action.cancelable
                        ? 'Reports progress live, and can be cancelled.'
                        : 'Reports progress live.',
                    style: TextStyle(
                        fontSize: 12.5, color: t.surface.onBaseMuted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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

  /// A param is declared by its config key (`callback_host`), which is a
  /// backend identifier — never show it raw. Same rule as everywhere else in
  /// the app: presented names are human-facing.
  Widget _param(ParamSpec p) {
    final t = HcTokens.of(context);
    final label = p.required ? humanize(p.name) : '${humanize(p.name)}  ·  optional';
    final help = switch (p.type) {
      // Surface the declared bounds — core and the plugin enforce them, so the
      // user should not have to discover them by being rejected.
      'integer' || 'number' when p.hasRange => [
          if (p.description != null) p.description!,
          '${p.minimum}–${p.maximum}',
        ].join(' · '),
      _ => p.description,
    };

    final field = switch (p.type) {
      _ when p.options != null => _dropdown(t, p),
      'boolean' => _toggle(t, p),
      _ => _text(t, p),
    };

    // Booleans carry their own inline label, so labelling twice would read as
    // a duplicate row.
    if (p.type == 'boolean') return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: t.surface.onBase)),
        SizedBox(height: t.space.xs),
        field,
        if (help != null) ...[
          SizedBox(height: t.space.xs),
          Text(help,
              style: TextStyle(fontSize: 11.5, color: t.surface.onBaseMuted)),
        ],
      ],
    );
  }

  InputDecoration _decoration(HcTokens t) => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: t.surface.sunken,
        contentPadding: EdgeInsets.symmetric(
            horizontal: t.space.md, vertical: t.space.sm + 2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.radius.md),
          borderSide: BorderSide(color: t.stroke.hairline, width: t.stroke.width),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.radius.md),
          borderSide: BorderSide(color: t.stroke.hairline, width: t.stroke.width),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.radius.md),
          borderSide: BorderSide(color: t.stroke.focus, width: t.stroke.width + 1),
        ),
      );

  Widget _dropdown(HcTokens t, ParamSpec p) => DropdownButtonFormField<String>(
        initialValue: _values[p.name] as String?,
        isExpanded: true,
        dropdownColor: t.surface.overlay,
        style: TextStyle(fontSize: 13.5, color: t.surface.onBase),
        decoration: _decoration(t),
        items: [
          for (final o in p.options!)
            DropdownMenuItem(value: o, child: Text(humanize(o))),
        ],
        onChanged: (v) => setState(() => _values[p.name] = v),
      );

  Widget _toggle(HcTokens t, ParamSpec p) => Row(
        children: [
          Switch(
            value: _values[p.name] == true,
            activeThumbColor: t.accent.active,
            onChanged: (v) => setState(() => _values[p.name] = v),
          ),
          SizedBox(width: t.space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(humanize(p.name),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: t.surface.onBase)),
                if (p.description != null)
                  Text(p.description!,
                      style: TextStyle(
                          fontSize: 11.5, color: t.surface.onBaseMuted)),
              ],
            ),
          ),
        ],
      );

  Widget _text(HcTokens t, ParamSpec p) {
    final numeric = p.type == 'integer' || p.type == 'number';
    return TextFormField(
      initialValue: _values[p.name]?.toString() ?? '',
      style: TextStyle(fontSize: 13.5, color: t.surface.onBase),
      decoration: _decoration(t),
      keyboardType: numeric ? TextInputType.number : null,
      onChanged: (v) => setState(() {
        if (!numeric) {
          _values[p.name] = v;
          return;
        }
        _values[p.name] = v.isEmpty
            ? null
            : (p.type == 'integer' ? int.tryParse(v) : num.tryParse(v));
      }),
    );
  }
}
