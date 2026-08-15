import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/svg_bindings.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/tokens.dart';
import 'widget_config_form.dart';

/// Where a drawing gets wired to the house.
///
/// The thing being edited is a sentence — *this element's this attribute
/// follows that device's that reading, over this range* — and the panel is
/// 320px wide, so each binding is a row that says the sentence and opens into
/// the fields when you want them. A flat form of six controls per binding
/// would be unreadable at four bindings, and four is a small drawing.
///
/// **The element list comes from the drawing itself.** Typing an id is how you
/// get a binding that silently does nothing; picking from what is actually in
/// the file is how you do not. Anything already bound is still shown — an id
/// that vanished because the drawing was replaced needs to be visible to be
/// fixed.
class SvgBindingsField extends ConsumerWidget {
  const SvgBindingsField({
    super.key,
    required this.config,
    required this.onChanged,
  });

  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value ?? const <DeviceState>[];
    final bindings = bindingsFromConfig(config);
    final ids = svgElementIds((config[svgSourceKey] as String?) ?? svgStarter);

    /// Writing bindings also **widens the grant to cover them**.
    ///
    /// Wiring a part to a device and then finding the drawing inert because the
    /// element was never given that device is a trap with no upside: naming a
    /// device in a binding *is* saying the drawing shows it. The grant stays
    /// explicit and visible — the device simply appears in the list below — so
    /// nothing is granted invisibly.
    ///
    /// Only for a hand-picked list. A grant expressed as a room, a kind or a
    /// search is a rule the author wrote, and quietly converting it to a list
    /// of ids would throw that rule away.
    void write(List<SvgBinding> next) {
      var updated = bindingsToConfig(config, next);
      final mode = updated['selection_mode'];
      if (mode == null || mode == 'manual') {
        final ids = <String>{
          ...((updated['device_ids'] as List?) ?? const []).map((e) => '$e'),
          for (final b in next)
            if (b.deviceId.isNotEmpty) b.deviceId,
        }..removeWhere((id) => id.isEmpty);
        updated = {
          ...updated,
          'selection_mode': 'manual',
          'device_ids': ids.toList(),
        };
      }
      onChanged(updated);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bindings.isEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: t.space.xs),
            child: Text(
              ids.isEmpty
                  ? 'This drawing has no ids on it. Give the parts you want to '
                      'drive an id in your editor, and they will appear here.'
                  : 'Nothing is wired up yet. The drawing has '
                      '${ids.length} named ${ids.length == 1 ? 'part' : 'parts'}.',
              style: t.text.captionStyle
                  .copyWith(color: t.surface.onBaseMuted, height: 1.4),
            ),
          ),
        for (final (i, binding) in bindings.indexed)
          _BindingRow(
            key: ValueKey('binding-$i'),
            binding: binding,
            ids: ids,
            devices: devices,
            // A change arrives as a *mutation*, applied here against the list
            // as it is now. Taking a finished object instead let two edits in
            // quick succession clobber one another: each field built its
            // replacement from the binding it was drawn with, so a keystroke
            // landing before the parent rebuilt wrote back a copy that still
            // had the previous field's value missing. Setting a range's four
            // numbers in a row lost one of them, silently, and the drawing
            // then ignored the range it appeared to have.
            onChanged: (change) => write([
              for (final (j, b) in bindings.indexed)
                if (j == i) change(b) else b,
            ]),
            onRemove: () => write([
              for (final (j, b) in bindings.indexed)
                if (j != i) b,
            ]),
          ),
        SizedBox(height: t.space.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => write([
              ...bindings,
              SvgBinding(
                // Pre-filled with the first unused id, because the common case
                // is binding the parts in the order they were drawn.
                elementId: ids
                        .where((id) => !bindings.any((b) => b.elementId == id))
                        .firstOrNull ??
                    (ids.firstOrNull ?? ''),
                attribute: 'stroke-dashoffset',
                deviceId: '',
                key: '',
              ),
            ]),
            icon: const Icon(Icons.add, size: 15),
            label: const Text('Wire up a part'),
          ),
        ),
      ],
    );
  }
}

class _BindingRow extends StatefulWidget {
  const _BindingRow({
    super.key,
    required this.binding,
    required this.ids,
    required this.devices,
    required this.onChanged,
    required this.onRemove,
  });

  final SvgBinding binding;
  final List<String> ids;
  final List<DeviceState> devices;

  /// Applied against the binding as it is when the write happens, never
  /// against the one this row was built with.
  final void Function(SvgBinding Function(SvgBinding current)) onChanged;

  final VoidCallback onRemove;

  @override
  State<_BindingRow> createState() => _BindingRowState();
}

class _BindingRowState extends State<_BindingRow> {
  /// Open while it is unfinished, because a row you have just added is a row
  /// you are about to fill in.
  late bool _open = !widget.binding.isComplete;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final b = widget.binding;
    final device = widget.devices.where((d) => d.id == b.deviceId).firstOrNull;

    return Container(
      margin: EdgeInsets.only(bottom: t.space.xs),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.radius.sm),
        border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: t.space.sm, vertical: t.space.xs),
              child: Row(
                children: [
                  Icon(_open ? Icons.expand_more : Icons.chevron_right,
                      size: 14, color: t.surface.onBaseMuted),
                  SizedBox(width: t.space.xs),
                  Expanded(
                    child: Text(
                      // The sentence, as far as it has been written.
                      b.isComplete
                          ? '#${b.elementId} · ${b.attribute} ← '
                              '${device?.displayName ?? b.deviceId}'
                          : b.elementId.isEmpty
                              ? 'A new binding'
                              : '#${b.elementId} — unfinished',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.text.captionStyle.copyWith(
                          color: b.isComplete
                              ? t.surface.onBase
                              : t.surface.onBaseMuted),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.close, size: 14),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove this binding',
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding:
                  EdgeInsets.fromLTRB(t.space.sm, 0, t.space.sm, t.space.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Field(
                    label: 'Part',
                    child: _Dropdown(
                      value: b.elementId,
                      // Whatever is bound stays offerable even if the drawing
                      // no longer has it, so a broken binding can be seen and
                      // repaired rather than silently rewritten.
                      options: {...widget.ids, b.elementId}
                          .where((e) => e.isNotEmpty)
                          .toList(),
                      onChanged: (v) =>
                          widget.onChanged((c) => c.copyWith(elementId: v)),
                    ),
                  ),
                  _Field(
                    label: 'Sets',
                    child: _Dropdown(
                      value: b.attribute,
                      options: {
                        SvgBinding.textAttribute,
                        ...svgCommonAttributes,
                        b.attribute,
                      }.where((e) => e.isNotEmpty).toList(),
                      onChanged: (v) =>
                          widget.onChanged((c) => c.copyWith(attribute: v)),
                    ),
                  ),
                  _Field(
                    label: 'From',
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await pickDevices(
                          context,
                          widget.devices,
                          single: true,
                          selected: {if (b.deviceId.isNotEmpty) b.deviceId},
                        );
                        if (picked == null) return;
                        widget.onChanged((c) => c.copyWith(
                            deviceId: picked.isEmpty ? '' : picked.first));
                      },
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          device?.displayName ?? 'Choose a device…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.text.captionStyle.copyWith(
                              color: device == null
                                  ? t.surface.onBaseMuted
                                  : t.surface.onBase),
                        ),
                      ),
                    ),
                  ),
                  _Field(
                    label: 'Reading',
                    child: _Dropdown(
                      value: b.key,
                      options: _readingsOf(device, b.key),
                      hint: device == null ? 'Pick a device first' : null,
                      onChanged: (v) =>
                          widget.onChanged((c) => c.copyWith(key: v)),
                    ),
                  ),
                  if (b.isText)
                    _Field(
                      label: 'Decimals',
                      child: _NumberField(
                        value: b.decimals?.toDouble(),
                        hint: 'trimmed',
                        onChanged: (v) => widget
                            .onChanged((c) => c.copyWith(decimals: v?.toInt())),
                      ),
                    )
                  else ...[
                    SizedBox(height: t.space.xs),
                    Text('RANGE',
                        style: t.text.overlineStyle
                            .copyWith(color: t.surface.onBaseMuted)),
                    SizedBox(height: t.space.xs),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            value: b.inFrom,
                            hint: 'from',
                            onChanged: (v) =>
                                widget.onChanged((c) => c.copyWith(inFrom: v)),
                          ),
                        ),
                        SizedBox(width: t.space.xs),
                        Expanded(
                          child: _NumberField(
                            value: b.inTo,
                            hint: 'to',
                            onChanged: (v) =>
                                widget.onChanged((c) => c.copyWith(inTo: v)),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: t.space.xs),
                          child: Icon(Icons.arrow_forward,
                              size: 13, color: t.surface.onBaseMuted),
                        ),
                        Expanded(
                          child: _NumberField(
                            value: b.outFrom,
                            hint: 'from',
                            onChanged: (v) =>
                                widget.onChanged((c) => c.copyWith(outFrom: v)),
                          ),
                        ),
                        SizedBox(width: t.space.xs),
                        Expanded(
                          child: _NumberField(
                            value: b.outTo,
                            hint: 'to',
                            onChanged: (v) =>
                                widget.onChanged((c) => c.copyWith(outTo: v)),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: t.space.xs),
                    Text(
                      b.hasRange
                          ? 'The reading runs ${_trim(b.inFrom!)}–'
                              '${_trim(b.inTo!)}; the attribute runs '
                              '${_trim(b.outFrom!)}–${_trim(b.outTo!)}.'
                          : 'Leave the range empty to set the attribute to the '
                              'reading itself.',
                      style: t.text.captionStyle
                          .copyWith(color: t.surface.onBaseMuted, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// What this device can be read for, with whatever is already bound kept in
  /// the list so a stale key is visible rather than silently blank.
  List<String> _readingsOf(DeviceState? device, String current) {
    final keys = <String>{
      ...?device?.state.keys,
      ...?device?.schema?.attributes.keys,
      if (current.isNotEmpty) current,
    }.toList()
      ..sort();
    return keys;
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: t.space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.xs / 2),
          child,
        ],
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: options.contains(value) && value.isNotEmpty ? value : null,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        hintText: hint,
      ),
      items: [
        for (final option in options)
          DropdownMenuItem(
            value: option,
            child: Text(
              option == SvgBinding.textAttribute
                  ? 'the text'
                  : humanize(option),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final double? value;
  final ValueChanged<double?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value == null
          ? ''
          : (value == value!.roundToDouble()
              ? value!.toStringAsFixed(0)
              : '$value'),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        hintText: hint,
      ),
      onChanged: (raw) =>
          onChanged(raw.trim().isEmpty ? null : double.tryParse(raw.trim())),
    );
  }
}
