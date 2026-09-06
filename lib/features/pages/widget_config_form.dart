import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/card_style.dart' show inkColours, resolveInk;
import '../../core/dashboard/widget_registry.dart';
import '../../core/providers/dashboard_vocabulary_provider.dart';
import '../../core/devices/scene_state.dart';
import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/schema/device_schema.dart';
import '../../core/models/scene.dart';
import '../../core/providers/areas_provider.dart';
import '../../core/providers/scenes_provider.dart';
import '../../core/providers/dashboards_provider.dart';
import '../../core/dashboard/room_scope.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/tokens.dart';
import '../../shell/hc_sheet.dart';
import '../devices/device_query.dart';
import '../assets/asset_field.dart';
import '../dashboard/home_plan_field.dart';
import '../../core/dashboard/svg_bindings.dart';
import '../dashboard/svg_card.dart';
import 'code_editor_sheet.dart';
import 'inspector_fields.dart';
import 'svg_bindings_field.dart';

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
              // The running config, not the one the sheet opened with: the form
              // reads this as the current state rather than keeping a copy.
              descriptor: widget.descriptor,
              initial: _config,
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
  /// The config as it is *now*, straight from the model — not a copy taken when
  /// the form was built.
  ///
  /// It used to be a `late final` copy, which made the form the authority on a
  /// value it does not own. Anything else that wrote to the same config — and
  /// as of the style pane, something does — would be silently reverted by the
  /// next keystroke here, because the form would re-emit the whole map from its
  /// stale copy. Both callers now feed the current config back down, so this is
  /// a pure view of it.
  Map<String, dynamic> get _config => widget.initial;
  String? _error;

  void _set(String name, Object? value) => _patch({name: value});

  /// Several keys at once, because one field can be one decision spread over
  /// more than one key — and applying them one at a time would rebuild from
  /// `initial` in between and lose all but the last.
  void _patch(Map<String, Object?> values) => setState(() {
        final next = {...widget.initial};
        for (final entry in values.entries) {
          if (entry.value == null) {
            next.remove(entry.key);
          } else {
            next[entry.key] = entry.value;
          }
        }
        widget.onChanged(next);
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
      // Shown for all three, because a room narrows a facet or a query as well
      // as being a rule of its own — "the lights in this room" is a thing a
      // page needs to say and could not.
      'area_name' => mode == 'area' || mode == 'facet' || mode == 'query',
      'query' => mode == 'query',
      'facet' => mode == 'facet',
      // Whatever the rule, you can take a kind back out of it.
      'except' => true,
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

    // Grouped, in the order the card declared them. A `Map` keyed by the group
    // name preserves insertion order in Dart, so the panel's sections come out
    // in the order the card thought of them rather than alphabetically — which
    // is the difference between "shape, fill, stroke, transform" and "fill,
    // shape, stroke, transform".
    final groups = <String?, List<WidgetConfigField>>{};
    for (final f in fields) {
      (groups[f.group] ??= []).add(f);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in groups.entries)
          if (entry.key case final title?)
            InspectorSection(
              title: title,
              children: [for (final f in entry.value) _field(f)],
            )
          else ...[for (final f in entry.value) _field(f)],
        if (_error != null)
          Padding(
            padding: EdgeInsets.only(top: t.space.xs),
            child: Text(_error!,
                style: t.text.bodySmallStyle.copyWith(color: t.accent.danger)),
          ),
      ],
    );
  }

  /// The message the card's own validator gives, or null when it is happy.
  String? get validationError => widget.descriptor.validate?.call(_config);

  // -- field dispatch --------------------------------------------------------

  Widget _field(WidgetConfigField f) => switch (f.kind) {
        WidgetConfigKind.boolean => _boolean(f),
        WidgetConfigKind.choice => _choice(f),
        WidgetConfigKind.integer => _number(f),
        WidgetConfigKind.markdown => _text(f, lines: 5),
        WidgetConfigKind.code => _code(f),
        WidgetConfigKind.svgSource => _svgSource(f),
        WidgetConfigKind.svgBindings => _svgBindings(f),
        WidgetConfigKind.url || WidgetConfigKind.text => _text(f),
        WidgetConfigKind.image => _image(f),
        WidgetConfigKind.homePlan => _homePlan(f),
        WidgetConfigKind.stringList => _stringList(f),
        WidgetConfigKind.choices => _choices(f),
        WidgetConfigKind.areaName => _area(f),
        WidgetConfigKind.facet => _facet(f),
        WidgetConfigKind.deviceRef => _deviceRef(f),
        WidgetConfigKind.deviceRefs => _deviceRefs(f),
        WidgetConfigKind.attribute => _attribute(f),
        WidgetConfigKind.writableAttribute => _writable(
            f,
            accepts: (s) => s.kind == AttributeKind.bool_,
            control: 'switch',
            nothing: 'accepts no on/off writes',
          ),
        WidgetConfigKind.writableNumber => _writable(
            f,
            accepts: (s) => s.kind.isNumeric,
            control: 'slider',
            nothing: 'accepts no numbers',
            showRange: true,
          ),
        WidgetConfigKind.writableColour => _writable(
            f,
            accepts: (s) =>
                s.kind == AttributeKind.colorXy ||
                s.kind == AttributeKind.colorRgb,
            control: 'colour wheel',
            nothing: 'accepts no colour',
          ),
        WidgetConfigKind.writableColourTemp => _writable(
            f,
            accepts: (s) => s.kind == AttributeKind.colorTemp,
            control: 'warmth bar',
            nothing: 'has no tunable white',
            showRange: true,
          ),
        WidgetConfigKind.sceneRef => _scene(f),
        WidgetConfigKind.sceneRefs => _scenes(f),
        WidgetConfigKind.ink => _ink(f),
        WidgetConfigKind.dashboardRef => _dashboard(f),
        WidgetConfigKind.pluginId => _pluginId(f),
        WidgetConfigKind.pluginWidgetId => _pluginWidgetId(f),
      };

  /// A colour, shown as the colour it is.
  ///
  /// A dropdown reading "Accent" tells you nothing about what the page will
  /// look like — the whole point of choosing a colour is seeing it. So the
  /// named colours are swatches drawn in the live skin, and the hex field
  /// behind them is for the one colour that has to match something outside the
  /// skin. Naming is offered first because a named colour *follows the skin*
  /// and a literal does not, which is the only consequential difference here.
  /// A colour: the colour itself on one line, its palette one click away.
  ///
  /// The grid of eleven swatches was the last control in the panel that was
  /// still shaped like a form — three rows for one setting, in a panel where
  /// every other setting is one line. A chip showing the colour *is* the state,
  /// which is what an inspector owes you; the palette is a choice, which is
  /// what a popover is for.
  Widget _ink(WidgetConfigField f) {
    final t = HcTokens.of(context);
    final value = _config[f.name] as String? ?? f.defaultValue as String?;
    final colour = resolveInk(t, value);
    final named = inkColours.where((i) => i.key == value).firstOrNull;
    return InspectorField(
      // A row called "Colour" under a heading called COLOUR is the panel
      // talking to itself. The heading has already said it.
      label: f.label == f.group ? '' : _title(f),
      help: f.help,
      child: _InkButton(
        colour: colour,
        label: named?.label ??
            (value == null
                ? 'None'
                : value.startsWith('#')
                    ? value.toUpperCase()
                    : humanize(value)),
        onPick: (at) => _pickInk(f, value, at),
      ),
    );
  }

  /// The palette, at the chip.
  ///
  /// Opened from the button's own context rather than the form's: `showMenu`
  /// takes a `RelativeRect` measured from the *overlay's edges*, so absolute
  /// coordinates passed to `fromLTRB` describe a rectangle that is not where
  /// the button is — which renders as a menu of the wrong size in the wrong
  /// place. `RelativeRect.fromRect` against the overlay does the arithmetic
  /// correctly and needs the button.
  Future<void> _pickInk(
      WidgetConfigField f, String? current, BuildContext at) async {
    final t = HcTokens.of(context);
    final button = at.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(at).context.findRenderObject() as RenderBox?;
    if (button == null || overlay == null) return;

    final picked = await showMenu<String?>(
      context: at,
      color: t.surface.overlay,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          button.localToGlobal(Offset.zero, ancestor: overlay),
          button.localToGlobal(button.size.bottomRight(Offset.zero),
              ancestor: overlay),
        ),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String?>(
          // Height stated, because a `PopupMenuItem` sizes to one row of text
          // by default and this one holds a grid.
          height: 0,
          padding: EdgeInsets.symmetric(
              horizontal: t.space.sm, vertical: t.space.sm),
          child: SizedBox(
            width: 196,
            child: Wrap(
              spacing: t.space.xs,
              runSpacing: t.space.xs,
              children: [
                // "None" first, because unset is a real answer for every one of
                // these — an unfilled shape, a line with no second colour, text
                // in the page's own ink — and it is not the same as any colour.
                _swatch(
                  key: null,
                  label: 'None',
                  colour: null,
                  on: current == null,
                ),
                for (final ink in inkColours)
                  _swatch(
                    key: ink.key,
                    label: ink.label,
                    colour: resolveInk(t, ink.key),
                    on: current == ink.key,
                  ),
                _swatch(
                  key: current != null && current.startsWith('#')
                      ? current
                      : '#4488ff',
                  label: 'Custom',
                  colour: current != null && current.startsWith('#')
                      ? resolveInk(t, current)
                      : null,
                  on: current != null && current.startsWith('#'),
                  custom: true,
                ),
              ],
            ),
          ),
        ),
        // Any colour, typed.
        //
        // The Custom swatch was a single hard-coded blue: one colour off the
        // palette and no way to reach a second, which meant a page could not
        // carry a brand colour or match a photograph. `resolveInk` has always
        // understood `#RRGGBB` — the picker simply had no way to say one.
        //
        // Under the palette rather than instead of it. A named ink follows the
        // skin, so a page built from the palette still looks right in every
        // one of the five; a hex is a decision to stop following, and it should
        // read as the more deliberate of the two.
        PopupMenuItem<String?>(
          height: 0,
          padding: EdgeInsets.fromLTRB(t.space.sm, 0, t.space.sm, t.space.sm),
          child: SizedBox(width: 196, child: _HexField(current: current)),
        ),
      ],
    );
    if (!mounted) return;
    // `showMenu` cannot tell "dismissed" from "picked None" through its own
    // return value, so the swatches pop the route themselves with a sentinel
    // and null here means the menu was dismissed.
    if (picked == null) return;
    _set(f.name, picked == _clearInk ? null : picked);
  }

  /// One colour in the palette. Pops the menu with its own value.
  Widget _swatch({
    required String? key,
    required String label,
    required Color? colour,
    required bool on,
    bool custom = false,
  }) {
    final t = HcTokens.of(context);
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(key ?? _clearInk),
        borderRadius: BorderRadius.circular(t.radius.sm),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: colour ?? t.surface.sunken,
            borderRadius: BorderRadius.circular(t.radius.sm),
            border: Border.all(
              color: on ? t.accent.active : t.stroke.hairline,
              // The chosen swatch is ringed, not ticked: a tick drawn over the
              // colour has to be legible on every colour, and there is no ink
              // that is.
              width: on ? 2 : t.stroke.width,
            ),
          ),
          child: colour == null
              ? Center(
                  child: Icon(
                    custom ? Icons.colorize_outlined : Icons.block_outlined,
                    size: 14,
                    color: t.surface.onBaseMuted,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _label(WidgetConfigField f, {bool section = false}) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.xs),
      child: Row(
        children: [
          // **A block of chips needs a heading, not a label.** Kind and Except
          // are two walls of pills one under the other, and their names were
          // set in the same body size as every other field's — so the eye read
          // one long list and the second block went unnoticed. John: *"the
          // kind/except are smaller and can go unnoticed."*
          Text(section ? _title(f).toUpperCase() : _title(f),
              style: section
                  ? t.text.overlineStyle.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: t.surface.onBaseMuted)
                  : t.text.bodySmallStyle.copyWith(
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

  /// Code, which is not edited here.
  ///
  /// The inspector shows what is there and how much of it, and opens the place
  /// it can actually be worked on. A textarea in a 340px column would be the
  /// same mistake as the five-line markdown field, one language further along.
  Widget _code(WidgetConfigField f) {
    final source = '${_config[f.name] ?? ''}';
    final lines = source.isEmpty ? 0 : '\n'.allMatches(source).length + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        OutlinedButton.icon(
          onPressed: () async {
            final next = await CodeEditorSheet.open(
              context,
              source: source,
              config: _config,
            );
            if (next == null) return;
            _set(f.name, next.isEmpty ? null : next);
          },
          icon: const Icon(Icons.code, size: 15),
          label: Text(lines == 0 ? 'Write it' : 'Edit code · $lines lines'),
        ),
        _help(f),
      ],
    );
  }

  /// The drawing, edited where it can be seen.
  Widget _svgSource(WidgetConfigField f) {
    final source = '${_config[f.name] ?? ''}';
    final ids = svgElementIds(source.isEmpty ? svgStarter : source);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        OutlinedButton.icon(
          onPressed: () async {
            final next = await CodeEditorSheet.open(
              context,
              source: source,
              config: _config,
              title: 'Drawing',
              hint: 'Paste an SVG. Give the parts you want to drive an id, '
                  'and they become bindable.',
              sourceKey: svgSourceKey,
              starter: svgStarter,
              // The preview is the bound card, so what you see while editing is
              // the drawing with the house in it rather than the raw file.
              preview: (config, onLog) => SvgCard(config: config, onLog: onLog),
            );
            if (next == null) return;
            _set(f.name, next.isEmpty ? null : next);
          },
          icon: const Icon(Icons.brush_outlined, size: 15),
          label: Text(source.isEmpty
              ? 'Paste a drawing'
              : 'Edit drawing · ${ids.length} named '
                  '${ids.length == 1 ? 'part' : 'parts'}'),
        ),
        _help(f),
      ],
    );
  }

  Widget _svgBindings(WidgetConfigField f) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        SvgBindingsField(config: _config, onChanged: widget.onChanged),
        _help(f),
      ],
    );
  }

  /// A picture, which may be uploaded rather than hosted first.
  ///
  /// The stored value is still a string, so a card configured before this
  /// existed keeps working and one configured with it is indistinguishable
  /// from a pasted address.
  /// The one field that owns more than its own key: the geometry and the
  /// storey being drawn are one decision, and splitting them across two fields
  /// would let a card point at a storey its home does not have.
  Widget _homePlan(WidgetConfigField f) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        HomePlanField(config: _config, onChanged: _patch),
        _help(f),
      ],
    );
  }

  Widget _image(WidgetConfigField f) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        AssetField(
          value: '${_config[f.name] ?? ''}',
          onChanged: (v) => _set(f.name, v.isEmpty ? null : v),
        ),
        _help(f),
      ],
    );
  }

  /// A number, on one line, with its name draggable.
  ///
  /// The single biggest difference between this panel and the form it replaces.
  /// A number used to be a heading, a bordered box the width of the panel and a
  /// line of help — three lines for a value between 0 and 360, which you could
  /// only change by selecting the text and typing another one. Now it is one
  /// line you can pull.
  Widget _number(WidgetConfigField f) {
    final raw = _config[f.name] ?? f.defaultValue;
    final value = raw is num ? raw : num.tryParse('${raw ?? ''}');
    return InspectorField(
      label: _title(f),
      help: f.help,
      // Scrubbing starts from the default when nothing is set, so pulling the
      // label of an unset rotation starts at 0 rather than doing nothing.
      onScrub: (steps) {
        final from =
            value ?? (f.defaultValue is num ? f.defaultValue as num : 0);
        var next = from + steps;
        if (f.min case final low?) next = next < low ? low : next;
        if (f.max case final high?) next = next > high ? high : next;
        _set(f.name, next);
      },
      child: InspectorNumber(
        value: value,
        unit: f.unit,
        min: f.min,
        max: f.max,
        // What the card does with nothing, said in the field rather than in a
        // paragraph under it.
        hint: f.defaultValue == null ? 'auto' : '${f.defaultValue}',
        onChanged: (v) => _set(f.name, v),
      ),
    );
  }

  Widget _boolean(WidgetConfigField f) => InspectorField(
        label: _title(f),
        help: f.help,
        child: InspectorSwitch(
          value: _config[f.name] == true,
          semanticLabel: _title(f),
          onChanged: (v) => _set(f.name, v),
        ),
      );

  /// A choice: every option at once when they fit, a menu when they do not.
  ///
  /// Alignment and Shape and Ends are three, four and two options with short
  /// names — showing them is strictly better than hiding them, because the
  /// panel then says which one is on without being touched.
  Widget _choice(WidgetConfigField f) {
    final options = f.options ?? const [];
    final value = _config[f.name] as String? ?? f.defaultValue as String?;
    return InspectorField(
      label: _title(f),
      help: f.help,
      child: InspectorChoice.segmented(options, humanize)
          ? InspectorSegments(
              options: options,
              value: value,
              labelFor: humanize,
              onChanged: (v) => _set(f.name, v),
            )
          : InspectorMenu(
              options: options,
              value: value,
              labelFor: humanize,
              hint: 'Choose',
              onChanged: (v) => _set(f.name, v),
            ),
    );
  }

  /// Some of a fixed set, as chips you toggle.
  ///
  /// An empty selection means *all of them* rather than none: a watch list
  /// nobody has touched should watch everything, and an element that went blank
  /// the moment you cleared the last chip would be a trap.
  /// Which chip blocks the person has opened. See [_choices].
  final _opened = <String>{};

  Widget _choices(WidgetConfigField f) {
    final t = HcTokens.of(context);
    final options = f.options ?? const <String>[];
    final chosen =
        ((_config[f.name] as List?) ?? const []).map((e) => '$e').toSet();

    // **An exception nobody has made should not cost twenty chips.** Except is
    // usually empty and always secondary — it takes back out of a rule what
    // the rule already chose — so folded it is one line that says its own name,
    // and open only when there is something in it or somebody asks.
    final open = _opened.contains(f.name) || chosen.isNotEmpty;
    if (!open) {
      return Padding(
        padding: EdgeInsets.only(bottom: t.space.xs),
        child: InkWell(
          onTap: () => setState(() => _opened.add(f.name)),
          borderRadius: t.radius.smR,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: t.space.xs),
            child: Row(
              children: [
                Text('${_title(f)} — none',
                    style: t.text.bodySmallStyle
                        .copyWith(color: t.surface.onBaseMuted)),
                const Spacer(),
                Icon(Icons.expand_more, size: 16, color: t.surface.onBaseMuted),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f, section: true),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final o in options)
              FilterChip(
                label: Text(humanize(o)),
                selected: chosen.contains(o),
                onSelected: (on) {
                  final next = {...chosen};
                  if (on) {
                    next.add(o);
                  } else {
                    next.remove(o);
                  }
                  _set(f.name, [
                    for (final o in options)
                      if (next.contains(o)) o
                  ]);
                },
              ),
          ],
        ),
        if (chosen.isEmpty) _hint('Nothing picked — all of them.'),
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
        _label(f, section: true),
        if (names.isEmpty)
          _hint(areasAsync.isLoading
              ? 'Loading areas…'
              : 'No areas yet. Assign devices to rooms in Manage, or pick '
                  'Manual/Query instead.')
        else
          DropdownButtonFormField<String>(
            initialValue:
                value == roomToken || names.contains(value) ? value : null,
            isExpanded: true,
            decoration: const InputDecoration(
                isDense: true, border: OutlineInputBorder()),
            items: [
              // First, because it is the answer a room page wants and naming
              // one of fifteen rooms on the page that serves all fifteen is
              // the mistake this exists to prevent.
              const DropdownMenuItem(
                  value: roomToken, child: Text('This room')),
              for (final n in names)
                DropdownMenuItem(value: n, child: Text(humanize(n))),
            ],
            onChanged: (v) => _set(f.name, v),
          ),
        if (value == roomToken)
          _hint('Whichever room the page was opened for. Room cards pass it; '
              'a page opened without one leaves this unresolved.'),
        _help(f),
      ],
    );
  }

  /// The kinds this house actually has, each with its live count.
  ///
  /// Only the kinds present, for the same reason the room list is built from
  /// the device map rather than from an enum: offering "Sirens 0" on a house
  /// with no siren is offering a card that will be empty, and finding that out
  /// by placing it is the discovery loop this arc exists to remove.
  ///
  /// The counts come from the same `facetGroupOf(facetOf(...))` the card
  /// filters on, so the number beside the name is the number you get.
  Widget _facet(WidgetConfigField f) {
    final devices = ref.watch(devicesProvider).value ?? const <DeviceState>[];
    final counts = <DeviceFacetGroup, int>{};
    for (final d in devices) {
      if (d.isSystem || d.deviceType == 'scene') continue;
      final group = facetGroupOf(facetOf(d, d.schema));
      counts[group] = (counts[group] ?? 0) + 1;
    }
    final present = counts.keys.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    // One or several: the stored value is a bare string when there is one kind
    // and a list when there are more, so every card written before this reads
    // unchanged.
    final raw = _config[f.name];
    final value = <String>{
      for (final k in raw is List ? raw : [raw])
        if (k is String && k.isNotEmpty) k,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        if (present.isEmpty)
          _hint('No devices yet, so there are no kinds to pick from.')
        else
          // Chips rather than a dropdown, because a panel can want more than
          // one kind: a room's "Lights" wants the lamps and the switches that
          // are lights in everything but their `device_type`.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final g in present)
                FilterChip(
                  label: Text('${g.label} · ${counts[g]}'),
                  selected: value.contains(g.key),
                  onSelected: (on) {
                    final next = {...value};
                    if (on) {
                      next.add(g.key);
                    } else {
                      next.remove(g.key);
                    }
                    // One kind stays a bare string, so a card edited here and
                    // read by an older build still means what it says.
                    final picked = [
                      for (final g in present)
                        if (next.contains(g.key)) g.key,
                    ];
                    _set(f.name, picked.length == 1 ? picked.first : picked);
                  },
                ),
            ],
          ),
        if (value.isEmpty) _hint('Nothing picked — this shows nothing.'),
        _help(f),
      ],
    );
  }

  /// Which plugin provides this card.
  ///
  /// The list is what this installation actually has, not what this build knows
  /// about — a plugin card is unknowable at compile time by construction. A
  /// core too old to be asked and a core with no plugin cards are told apart on
  /// purpose: the first is our ignorance and the second is a fact about the
  /// house, and offering an empty dropdown for either would say neither.
  Widget _pluginId(WidgetConfigField f) {
    final async = ref.watch(dashboardVocabularyProvider);
    final all = async.value?.pluginWidgets;
    final value = _config[f.name] as String?;

    if (async.isLoading) return _pickerShell(f, _hint('Asking core…'));
    if (all == null) return _manualFallback(f);
    if (all.isEmpty) {
      return _pickerShell(
        f,
        _hint('No plugin here contributes a card yet.'),
      );
    }

    final plugins = {for (final s in all) s.pluginId}.toList()..sort();
    return _pickerShell(
      f,
      DropdownButtonFormField<String>(
        initialValue: plugins.contains(value) ? value : null,
        isExpanded: true,
        decoration:
            const InputDecoration(isDense: true, border: OutlineInputBorder()),
        items: [
          for (final id in plugins)
            DropdownMenuItem(value: id, child: Text(id)),
        ],
        // Changing the plugin clears the card: the card that was chosen belongs
        // to the plugin that was chosen, and leaving it behind would name a
        // card the new plugin does not have.
        onChanged: (v) => _patch({f.name: v, 'widget_id': null}),
      ),
    );
  }

  /// Which of that plugin's cards.
  ///
  /// Titles, not ids: `boiler_flow` is what the plugin author typed and "Boiler
  /// flow" is what they meant. The id is still what gets stored, because it is
  /// what core validates against.
  Widget _pluginWidgetId(WidgetConfigField f) {
    final async = ref.watch(dashboardVocabularyProvider);
    final all = async.value?.pluginWidgets;
    final plugin = (_config['plugin_id'] as String? ?? '').trim();
    final value = _config[f.name] as String?;

    if (async.isLoading) return _pickerShell(f, _hint('Asking core…'));
    if (all == null) return _manualFallback(f);
    if (plugin.isEmpty) {
      return _pickerShell(f, _hint('Choose a plugin first.'));
    }

    final cards = all.where((s) => s.pluginId == plugin).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    if (cards.isEmpty) {
      return _pickerShell(
        f,
        // The plugin is chosen and gone, or chosen and contributing nothing.
        // Either way the card list is empty for a reason worth saying.
        _hint('$plugin contributes no cards right now.'),
      );
    }

    return _pickerShell(
      f,
      DropdownButtonFormField<String>(
        initialValue: cards.any((c) => c.widgetId == value) ? value : null,
        isExpanded: true,
        decoration:
            const InputDecoration(isDense: true, border: OutlineInputBorder()),
        items: [
          for (final c in cards)
            DropdownMenuItem(value: c.widgetId, child: Text(c.title)),
        ],
        onChanged: (v) => _set(f.name, v),
      ),
    );
  }

  /// Label, control, help.
  Widget _pickerShell(WidgetConfigField f, Widget control) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_label(f), control, _help(f)],
      );

  /// The plain text field the picker replaced, for a core that cannot be asked.
  ///
  /// Keeping it for that one case matters: a card pointed at a plugin has to
  /// stay editable against a core too old to list them, or upgrading core
  /// becomes a prerequisite for fixing a typo. The text field draws its own label
  /// and help, so the picker shell is deliberately not used here.
  Widget _manualFallback(WidgetConfigField f) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _hint('This core cannot list plugin cards, so type the id by hand.'),
          _text(f),
        ],
      );

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
    final devices = ref.watch(devicesProvider).value ?? const [];
    final id = _config[f.name] as String?;
    final selected = devices.where((d) => d.id == id).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pickRow(
          f,
          value: selected?.displayName,
          placeholder: 'Choose a device…',
          onTap: () async {
            final picked = await pickDevices(context, devices,
                single: true, selected: {if (id != null) id});
            if (picked != null) {
              _set(f.name, picked.isEmpty ? null : picked.first);
            }
          },
        ),
        _help(f),
      ],
    );
  }

  Widget _deviceRefs(WidgetConfigField f) {
    final devices = ref.watch(devicesProvider).value ?? const [];
    final ids =
        ((_config[f.name] as List?) ?? const []).map((e) => '$e').toSet();
    // Named rather than counted, for the same reason the scenes are: `6
    // selected` is a fact about the list, not about this page.
    final names = [
      for (final id in ids)
        devices
                .where((d) => d.id == id)
                .map((d) => d.displayName)
                .firstOrNull ??
            'one that is gone',
    ];
    return _pickRow(
      f,
      value: names.isEmpty ? null : names.join(', '),
      placeholder: 'Choose devices…',
      onTap: () async {
        final picked =
            await pickDevices(context, devices, single: false, selected: ids);
        if (picked != null) _set(f.name, picked);
      },
    );
  }

  /// The scenes this house has.
  ///
  /// A plain list, because a scene either exists or it does not — there is no
  /// writability question here the way there is for a device attribute.
  /// One of this house's other pages.
  ///
  /// The page this one is on is offered too. A dashboard that opens itself is
  /// a loop, but it is also how somebody builds a "back to the top" link on a
  /// long page, and refusing it would be this form deciding what they meant.
  Widget _dashboard(WidgetConfigField f) {
    final pages = ref.watch(dashboardsProvider).value ?? const [];
    final value = _config[f.name] as String?;
    final known = pages.any((d) => d.id == value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        if (pages.isEmpty)
          _hint('There are no other pages yet.')
        else
          DropdownButtonFormField<String>(
            initialValue: known ? value : null,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final page in pages)
                DropdownMenuItem(value: page.id, child: Text(page.name)),
            ],
            onChanged: (v) => _set(f.name, v),
          ),
        // A page deleted after this link was made. Said rather than silently
        // blanked, because the link is still on somebody's wall.
        if (value != null && value.isNotEmpty && !known && pages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'The page this opened is gone.',
              style: HcTokens.of(context)
                  .text
                  .captionStyle
                  .copyWith(color: HcTokens.of(context).accent.warn),
            ),
          ),
        _help(f),
      ],
    );
  }

  /// Both kinds of scene, in one list.
  ///
  /// Native scenes come from `/scenes`; plugin scenes arrive as devices with
  /// `device_type == 'scene'`. To whoever is drawing the page they are the same
  /// thing — a named thing you can run — and only the code that sends knows the
  /// difference, so a picker that offered one and not the other would hide half
  /// the house's scenes for no reason the author could see.
  /// Which scenes to show — a line, and the same searchable sheet a device
  /// goes through.
  ///
  /// **A wall of chips could not answer either question this has to.** A house
  /// with fifty-eight scenes has four called *Nightlight*, one per room, so a
  /// grid of names cannot say which one is which — and the ones already chosen
  /// were lifted out into a row of their own, where they read as a different
  /// list rather than as ticks against the same one. John: *"pre-selected
  /// scenes are not identified"*, and *"the boxes used throughout the editor
  /// for scenes and devices is not very nice."*
  ///
  /// So: the room is on every row, the chosen ones are ticked in place, and
  /// the panel keeps one line. Empty still means all of them.
  Widget _scenes(WidgetConfigField f) {
    final t = HcTokens.of(context);
    final all = _sceneChoices();
    final chosen =
        ((_config[f.name] as List?) ?? const []).whereType<String>().toList();

    String? nameOf(String id) =>
        all.where((c) => c.id == id).map((c) => c.name).firstOrNull;

    // Named, and in the order they will be drawn: a count alone leaves the one
    // question a person opens this panel to answer — *which six?* — needing a
    // second click to see.
    final named = [for (final id in chosen) nameOf(id) ?? 'one that is gone'];

    return _pickRow(
      f,
      value: chosen.isEmpty ? null : named.join(', '),
      placeholder: all.isEmpty ? 'No scenes yet' : 'Every scene',
      onTap: all.isEmpty
          ? null
          : () async {
              final picked = await pickScenes(context, all, selected: chosen);
              if (picked != null) _set(f.name, picked.isEmpty ? null : picked);
            },
      trailing: chosen.isEmpty
          ? null
          : IconButton(
              tooltip: 'Show every scene',
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => _set(f.name, null),
              color: t.surface.onBaseMuted,
              visualDensity: VisualDensity.compact,
            ),
    );
  }

  /// Every scene this house has, native and plugin alike, with where it lives.
  ///
  /// The room is not decoration: it is the only thing telling four scenes
  /// called *Nightlight* apart.
  List<SceneChoice> _sceneChoices() {
    final native = ref.watch(scenesProvider).value ?? const <SceneModel>[];
    final devices = ref.watch(devicesProvider).value ?? const <DeviceState>[];
    return <SceneChoice>[
      for (final s in native) (id: s.id, name: s.name, area: null),
      for (final d in devices)
        if (isSceneDevice(d))
          (id: d.id, name: d.displayName, area: d.effectiveArea),
    ]..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : (a.area ?? '').compareTo(b.area ?? '');
      });
  }

  /// One line: what is chosen, and a tap to change it.
  ///
  /// **The shape every "pick something" setting shares.** They were an
  /// outlined button the height of a text field, one under each label, which
  /// in a 320px panel is most of the panel — and each one said `Choose a
  /// device…` whether something was chosen or not.
  Widget _pickRow(
    WidgetConfigField f, {
    required String? value,
    required String placeholder,
    required VoidCallback? onTap,
    Widget? trailing,
  }) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // The name of the setting keeps its own column so the value can wrap
          // under nothing but itself.
          SizedBox(
            width: 96,
            child: Text(
              _title(f),
              style: t.text.bodySmallStyle.copyWith(
                  fontWeight: FontWeight.w600, color: t.surface.onBase),
            ),
          ),
          SizedBox(width: t.space.sm),
          // **It has to look like something you press.** As a bare line of
          // text with a chevron it read as a label with a value beside it, and
          // the way to choose scenes was to guess that the words were a
          // button. John: *"Not intuitive on how to select scenes within the
          // container."* A sunken field says *control* the way the old
          // outlined button did, at a fifth of the height.
          Expanded(
            child: Material(
              color: t.surface.sunken,
              borderRadius: t.radius.smR,
              child: InkWell(
                onTap: onTap,
                borderRadius: t.radius.smR,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: t.space.sm, vertical: t.space.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          value ?? placeholder,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.text.bodySmallStyle.copyWith(
                            color: value == null
                                ? t.surface.onBaseMuted
                                : t.surface.onBase,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 16, color: t.surface.onBaseMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _scene(WidgetConfigField f) {
    final native = ref.watch(scenesProvider).value ?? const <SceneModel>[];
    final devices = ref.watch(devicesProvider).value ?? const <DeviceState>[];

    final choices = <({String id, String name})>[
      for (final s in native) (id: s.id, name: s.name),
      for (final d in devices)
        if (isSceneDevice(d)) (id: d.id, name: d.displayName),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final value = _config[f.name] as String?;
    final known = choices.any((c) => c.id == value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        if (choices.isEmpty)
          _hint('This house has no scenes yet.')
        else
          DropdownButtonFormField<String>(
            initialValue: known ? value : null,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final c in choices)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => _set(f.name, v),
          ),
        // A scene that was deleted after the page was made. Said rather than
        // silently blanked, because the button is still on somebody's wall.
        if (value != null && value.isNotEmpty && !known && choices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'The scene this button used is gone.',
              style: HcTokens.of(context)
                  .text
                  .captionStyle
                  .copyWith(color: HcTokens.of(context).accent.warn),
            ),
          ),
        _help(f),
      ],
    );
  }

  /// The things this device has **promised** it accepts a write of.
  ///
  /// Only a registered schema counts. `attribute_policy.dart` is explicit about
  /// why: an inferred `writable` is this app's opinion, and attribute-style
  /// writes are not universal — `hc-sonos::execute_command` dispatches on an
  /// `action` and rejects `{"muted": true}` outright. A control built on the
  /// guess would look right, send, and change nothing.
  ///
  /// A device that registered nothing therefore offers nothing here, and says
  /// so. An empty dropdown would read as "this app is broken" rather than "that
  /// plugin never said".
  ///
  /// One method for all four writable kinds. They differ only in which specs
  /// they accept and what to call them when there are none — four copies of
  /// this list would be four places for the promise rule to drift out of step,
  /// which is exactly the failure it exists to prevent.
  Widget _writable(
    WidgetConfigField f, {
    required bool Function(AttributeSchema) accepts,
    required String control,
    required String nothing,
    bool showRange = false,
  }) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value ?? const [];
    final deviceId = _config['device_id'] as String?;
    final device = devices.where((d) => d.id == deviceId).firstOrNull;

    final specs = <String, AttributeSchema>{
      for (final e in (device?.schema?.writable ?? const {}).entries)
        if (accepts(e.value)) e.key: e.value,
    };
    final offered = specs.keys.toList()..sort();
    final value = _config[f.name] as String?;
    final chosen = specs[value];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f),
        if (device == null)
          _hint('Pick a device first.')
        else if (device.schema == null)
          _hint('${device.displayName} has never told core what it accepts, '
              'so nothing here can promise a $control will work.')
        else if (offered.isEmpty)
          _hint('${device.displayName} $nothing.')
        else
          DropdownButtonFormField<String>(
            initialValue: offered.contains(value) ? value : null,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final a in offered)
                DropdownMenuItem(value: a, child: Text(humanize(a))),
            ],
            onChanged: (v) => _set(f.name, v),
          ),
        _help(f),
        // The plugin's own range, where the control will actually use it — an
        // author should see it before wondering why the handle stops.
        if (showRange && chosen != null)
          Padding(
            padding: EdgeInsets.only(top: t.space.xs),
            child: Text(
              chosen.hasRange
                  ? 'The plugin says ${_trimNum(chosen.min!)} to '
                      '${_trimNum(chosen.max!)}'
                      '${chosen.unit == null ? '' : ' ${chosen.unit}'}.'
                  : 'The plugin gave no range, so this $control needs one '
                      'below.',
              style: t.text.captionStyle.copyWith(
                color: chosen.hasRange ? t.accent.success : t.accent.warn,
              ),
            ),
          )
        else if (!showRange && device?.schema != null && offered.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: t.space.xs),
            child: Text(
              'Registered by the plugin, not guessed.',
              style: t.text.captionStyle.copyWith(color: t.accent.success),
            ),
          ),
      ],
    );
  }

  /// 100, not 100.0 — a range read by a person.
  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

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

/// One scene as the picker sees it: what it is called, and where it lives.
typedef SceneChoice = ({String id, String name, String? area});

/// The scene picker every field that names scenes goes through.
///
/// **The same sheet a device goes through, for the same reasons.** A house
/// with fifty-eight scenes needs searching, and four of them are called
/// *Nightlight* — one per room — so the room is on the row rather than being
/// something you find out by choosing wrong. The ones already chosen are
/// ticked, in place, in the list they came from.
///
/// Returns the ids in the order they will be drawn: the ones already picked
/// keep the order somebody put them in, and anything ticked today goes on the
/// end. Reordering by re-ticking would mean a person opening this to add one
/// scene came out with six in a different order.
Future<List<String>?> pickScenes(
  BuildContext context,
  List<SceneChoice> scenes, {
  required List<String> selected,
}) {
  return showHcSheet<List<String>>(
    context,
    title: 'Pick scenes',
    child: _ScenePicker(scenes: scenes, initial: selected),
  );
}

class _ScenePicker extends StatefulWidget {
  const _ScenePicker({required this.scenes, required this.initial});

  final List<SceneChoice> scenes;
  final List<String> initial;

  @override
  State<_ScenePicker> createState() => _ScenePickerState();
}

class _ScenePickerState extends State<_ScenePicker> {
  late final List<String> _selected = [...widget.initial];
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final q = _query.toLowerCase();
    final matches = widget.scenes
        .where((s) =>
            q.isEmpty ||
            s.name.toLowerCase().contains(q) ||
            (s.area ?? '').toLowerCase().contains(q))
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HcSheetHeader(title: 'Pick scenes'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space.lg),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search scenes',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SizedBox(height: t.space.sm),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space.lg),
          child: Text(
            // What an empty pick means, said where the decision is made.
            _selected.isEmpty
                ? 'Nothing picked shows every scene.'
                : '${_selected.length} of ${widget.scenes.length}, in the '
                    'order you picked them.',
            style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
          ),
        ),
        SizedBox(height: t.space.sm),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.symmetric(horizontal: t.space.md),
            itemCount: matches.length,
            itemBuilder: (context, i) {
              final s = matches[i];
              final on = _selected.contains(s.id);
              // A ListTile paints its ink on the nearest Material ancestor,
              // and the sheet's surface is a DecoratedBox — without this every
              // tap in the picker looks like nothing happened.
              return Material(
                type: MaterialType.transparency,
                child: CheckboxListTile(
                  dense: true,
                  value: on,
                  title: Text(s.name,
                      style:
                          t.text.bodyStyle.copyWith(color: t.surface.onBase)),
                  subtitle: Text(
                    (s.area ?? '').isEmpty ? 'Whole house' : humanize(s.area!),
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted),
                  ),
                  onChanged: (_) => setState(
                      () => on ? _selected.remove(s.id) : _selected.add(s.id)),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.all(t.space.lg),
          child: Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(const <String>[]),
                child: const Text('Show every scene'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              SizedBox(width: t.space.sm),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_selected),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A searchable device picker, single or multi. Returns the chosen ids, or null
/// if dismissed. 167 devices is too many for a dropdown, so this searches.
/// The device picker every field that names a device goes through.
///
/// Public because the SVG binding editor asks the same question in a different
/// panel, and two pickers that drift apart is how "choose a device" comes to
/// mean two things.
Future<List<String>?> pickDevices(
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
              // A ListTile paints its ink on the nearest Material ancestor, and
              // the sheet's own surface is a DecoratedBox — so without this the
              // splash is drawn behind the background and every tap in the
              // picker looks like nothing happened. Flutter says so out loud in
              // debug; in release it is simply a list that feels dead.
              return Material(
                type: MaterialType.transparency,
                child: CheckboxListTile(
                  dense: true,
                  value: on,
                  title: Text(d.displayName,
                      style:
                          t.text.bodyStyle.copyWith(color: t.surface.onBase)),
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
                ),
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

/// What a swatch pops with when it means *no colour*.
///
/// `showMenu` returns null for a dismissal, so "unset" needs a value of its
/// own — otherwise choosing None and pressing Escape would be the same event.
const _clearInk = '__none__';

/// The current colour, as a chip you can read and click.
class _InkButton extends StatelessWidget {
  const _InkButton({
    required this.colour,
    required this.label,
    required this.onPick,
  });

  final Color? colour;
  final String label;

  /// Handed the button's own `BuildContext`, which is what the menu needs to
  /// know where it is.
  final ValueChanged<BuildContext> onPick;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return InkWell(
      onTap: () => onPick(context),
      borderRadius: BorderRadius.circular(t.radius.xs),
      child: Container(
        height: t.density.controlHeight,
        padding: EdgeInsets.symmetric(horizontal: t.space.xs),
        decoration: BoxDecoration(
          color: t.surface.sunken,
          borderRadius: BorderRadius.circular(t.radius.xs),
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: colour ?? t.surface.base,
                borderRadius: BorderRadius.circular(t.radius.xs),
                border:
                    Border.all(color: t.stroke.hairline, width: t.stroke.width),
              ),
              // An unset colour is not a colour, so it is drawn as absence
              // rather than as a black square that looks like a choice.
              child: colour == null
                  ? Icon(Icons.block_outlined,
                      size: 12, color: t.surface.onBaseMuted)
                  : null,
            ),
            SizedBox(width: t.space.xs),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A colour typed as hex, inside the palette popover.
///
/// Pops the menu with the value the moment it is a colour, so typing six digits
/// and pressing Enter picks it — the same gesture as clicking a swatch, not a
/// second dialog to dismiss afterwards.
class _HexField extends StatefulWidget {
  const _HexField({required this.current});

  final String? current;

  @override
  State<_HexField> createState() => _HexFieldState();
}

class _HexFieldState extends State<_HexField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current != null && widget.current!.startsWith('#')
        ? widget.current!.substring(1).toUpperCase()
        : '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// `#RRGGBB` from what was typed, or null when it is not one yet.
  ///
  /// Accepts a leading `#` and either case, because both are what people paste.
  /// Three digits are not expanded: `#FFF` is a shorthand this app's resolver
  /// does not read, and silently turning it into something else would be
  /// picking a colour nobody chose.
  static String? _colour(String raw) {
    final hex = raw.trim().replaceFirst('#', '').toUpperCase();
    if (hex.length != 6 && hex.length != 8) return null;
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(hex)) return null;
    return '#$hex';
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final parsed = _colour(_controller.text);
    return TextField(
      controller: _controller,
      autofocus: false,
      onChanged: (_) => setState(() {}),
      onSubmitted: (v) {
        final picked = _colour(v);
        if (picked != null) Navigator.of(context).pop(picked);
      },
      style: t.text.bodySmallStyle.copyWith(
        color: t.surface.onBase,
        fontFamily: t.text.monoFamily,
      ),
      decoration: InputDecoration(
        isDense: true,
        prefixText: '#',
        prefixStyle: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
        hintText: 'RRGGBB',
        border: const OutlineInputBorder(),
        contentPadding:
            EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.sm),
        // The colour it would be, shown before you commit to it.
        suffixIcon: parsed == null
            ? null
            : Padding(
                padding: EdgeInsets.only(right: t.space.sm),
                child: Center(
                  widthFactor: 1,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: resolveInk(t, parsed),
                      borderRadius: t.radius.xsR,
                      border: Border.all(color: t.stroke.hairline),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
