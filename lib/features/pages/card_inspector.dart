import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/binding.dart';
import '../../core/dashboard/card_condition.dart';
import '../../core/dashboard/tap_action.dart';
import '../../core/dashboard/card_style.dart';
import '../../core/dashboard/grid_engine.dart' show DashboardRect;
import '../../core/dashboard/free_layer.dart';
import '../../core/dashboard/transform.dart';
import '../../core/dashboard/widget_registry.dart';
import '../../core/devices/scene_state.dart';
import '../../core/models/device_state.dart';
import '../../core/models/dashboard.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/dashboards_provider.dart';
import '../../core/providers/modes_provider.dart';
import '../../core/providers/scenes_provider.dart';
import '../../core/schema/device_schema.dart';
import '../../core/text/humanize.dart';
import '../../design/tokens.dart';
import '../assets/asset_field.dart';
import '../dashboard/builtin_cards.dart';
import 'card_members.dart';
import 'widget_config_form.dart';

/// The selected card's settings, beside the canvas.
///
/// Step 5 of `dashboard-authoring-plan.md`. Configuring a card meant a sheet
/// **over** the page: you changed a setting, pressed Done, the sheet closed,
/// and only then did you find out what you had done. That is how two shipped
/// templates matching zero devices went unnoticed for as long as they did.
///
/// Two things follow from putting it beside the canvas instead of over it:
///
/// **Edits apply immediately.** There is nothing to commit — the page's own
/// Cancel and Done already govern the draft, and a second pair inside it only
/// ever meant "commit to the buffer". You change the room and watch the card
/// become that room.
///
/// **It can say what the card will hold.** `31 devices · showing first 12`,
/// counted with the same function the card renders from, so the two cannot
/// disagree. A card about to be empty says `No devices match` here, before it
/// is ever saved — which is the whole point.
class CardInspector extends ConsumerStatefulWidget {
  const CardInspector({
    super.key,
    required this.model,
    required this.onChanged,
    required this.onRemove,
    required this.onClose,
    this.onRename,
    this.floating = false,
    this.z = 0,
    this.onStack,
    this.rotation,
    this.opacity,
    this.onRotate,
    this.onFade,
    this.rect,
    this.onRect,
  });

  final DashboardWidgetModel model;

  /// A config the user has just edited. Applied to the draft immediately.
  final ValueChanged<Map<String, dynamic>> onChanged;

  final VoidCallback onRemove;
  final VoidCallback onClose;

  /// Rename the card.
  ///
  /// Nothing could do this before. A card took the label of whatever library
  /// entry produced it and kept it for good, so a page could end up with two
  /// cards both called "Several devices" and no way to tell them apart — here,
  /// on the page, or in the layers strip that lists them by name.
  final ValueChanged<String>? onRename;

  /// Where this card sits relative to the grid, and how high in the stack.
  final bool floating;
  final int z;

  /// Null outside the designer, where nothing can be restacked.
  final ValueChanged<StackMove>? onStack;

  /// The card's own transform, from its *placement* rather than its config.
  ///
  /// Null outside the designer, where nothing can be turned. Both values live
  /// on the placement because an angle is a property of an arrangement — see
  /// `docs/dashboard-layout.md`.
  final double? rotation;
  final double? opacity;

  /// Turn the card, or fade it. Null means the pair is not offered.
  ///
  /// Two callbacks rather than one taking both, because `null` is a real value
  /// here — clearing a rotation back to none is an edit — and a single call
  /// carrying two nullables could not say which of the two it meant.
  final ValueChanged<double?>? onRotate;
  final ValueChanged<double?>? onFade;

  /// The element's own rectangle, when it has one.
  ///
  /// Null for a card the grid engine packs — it has no x it could be told,
  /// because the engine decides. Four fields that silently did nothing would
  /// be worse than none.
  final DashboardRect? rect;

  /// Move or resize it by typing. Null means the fields are not offered.
  final ValueChanged<DashboardRect>? onRect;

  @override
  ConsumerState<CardInspector> createState() => _CardInspectorState();
}

class _CardInspectorState extends ConsumerState<CardInspector> {
  /// Explicit, because an unmanaged scroll view on Flutter web draws no
  /// scrollbar at all — the same finding the canvas records two files away.
  /// A card with a long form then had fields below the fold with nothing on
  /// screen admitting they were there, and the wheel did not reach them.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final onChanged = widget.onChanged;
    final onRename = widget.onRename;
    final onStack = widget.onStack;
    final t = HcTokens.of(context);
    final descriptor = WidgetRegistry.lookup(model.type);

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: t.surface.raised,
        borderRadius: BorderRadius.circular(t.radius.md),
        border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
      ),
      padding: EdgeInsets.all(t.space.md),
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.only(right: t.space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      model.title.trim().isEmpty
                          ? (descriptor?.title ?? model.type)
                          : model.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.text.subtitleStyle.copyWith(
                          color: t.surface.onBase, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: 'Done with this card',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (descriptor != null)
                Text(descriptor.title,
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted)),
              SizedBox(height: t.space.md),
              if (descriptor == null)
                Text('This card type is not installed.',
                    style: t.text.bodySmallStyle
                        .copyWith(color: t.surface.onBaseMuted))
              else ...[
                WidgetConfigForm(
                  // Keyed by card, or moving the selection to another card would
                  // reuse the previous one's field state — its text controllers
                  // still holding the last card's values.
                  key: ValueKey(model.id),
                  descriptor: descriptor,
                  initial: model.config,
                  onChanged: onChanged,
                ),
                // The card's own validator, inline. There is no Done here to
                // hang it off, and an unsaveable card must say so where it is
                // being edited rather than at the page's save.
                if (descriptor.validate?.call(model.config) case final message?)
                  Padding(
                    padding: EdgeInsets.only(bottom: t.space.xs),
                    child: Text(
                      message,
                      style: t.text.bodySmallStyle
                          .copyWith(color: t.accent.danger),
                    ),
                  ),
                _Preview(config: model.config, descriptor: descriptor),
                // Which devices, listed and tickable — for the card types whose
                // contents are a device selection. A room card was a live query
                // with nothing showing what it held.
                if (_selects(descriptor.type))
                  CardMembers(config: model.config, onChanged: onChanged),
              ],
              // Style is offered only where there is a card to un-draw. A
              // heading, a rule and a spacer have no surface at all, so a
              // "background" switch on one would be a control with nothing
              // behind it.
              if (onRename != null)
                _NameField(
                  key: ValueKey('title-${model.id}'),
                  value: model.title,
                  hint: descriptor?.title ?? model.type,
                  onChanged: onRename,
                ),
              if (descriptor != null &&
                  descriptor.chrome != WidgetChrome.bare) ...[
                _StyleSection(
                  cardId: model.id,
                  style: CardStyle.fromConfig(model.config),
                  onChanged: (style) => onChanged(style.toConfig(model.config)),
                ),
                _VariantsSection(
                  style: CardStyle.fromConfig(model.config),
                  onChanged: (style) => onChanged(style.toConfig(model.config)),
                ),
              ],
              // Outside the chrome test above: an element with no surface —
              // an icon, a shape — is exactly the kind of thing worth binding,
              // so this must not hang off whether the card has a frame.
              if (descriptor != null && descriptor.bindable.isNotEmpty)
                _DataSection(
                  descriptor: descriptor,
                  config: model.config,
                  onChanged: onChanged,
                ),
              if (widget.rect != null && widget.onRect != null)
                _PositionSection(
                  rect: widget.rect!,
                  rotation: widget.rotation,
                  onRect: widget.onRect!,
                  onRotate: widget.onRotate ?? (_) {},
                ),
              if (widget.onRotate case final onRotate?)
                _TransformSection(
                  rotation: widget.rotation,
                  opacity: widget.opacity,
                  onRotate: onRotate,
                  onFade: widget.onFade ?? (_) {},
                ),
              if (onStack != null)
                _StackSection(
                    floating: widget.floating, z: widget.z, onStack: onStack),
              // Every element, not only the ones that thought to ask. An
              // action belongs to all of them or to none — see `_TapSection`.
              _TapSection(config: model.config, onChanged: onChanged),
              // Last, and folded: the drawn controls above are how you are
              // meant to work. This is the hatch for everything they do not
              // reach — including keys this version of this app has never
              // heard of.
              _AllPropertiesSection(config: model.config, onChanged: onChanged),
              SizedBox(height: t.space.md),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: widget.onRemove,
                  child: Text('Remove from page',
                      style: TextStyle(color: t.accent.danger)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What this card will actually contain, right now.
class _Preview extends ConsumerWidget {
  const _Preview({required this.config, required this.descriptor});

  final Map<String, dynamic> config;
  final WidgetDescriptor descriptor;

  /// Cards whose contents are a device selection. Anything else has nothing to
  /// preview here — a note or a web page is its own preview, on the canvas.
  static const _deviceCards = {
    'device_grid',
    'device_list',
    'device_tile',
    'media_player',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_deviceCards.contains(descriptor.type)) return const SizedBox.shrink();
    // A config the card rejects has no meaningful preview. Mode "area" with no
    // area picked selects everything, so this would have announced "123
    // devices" for a card that cannot be saved at all — a confident number in
    // place of the reason.
    if (descriptor.validate?.call(config) != null) {
      return const SizedBox.shrink();
    }
    final t = HcTokens.of(context);
    final async = ref.watch(devicesProvider);
    if (async.value == null) return const SizedBox.shrink();

    final selection = selectDevicesWithCount(async.value!, config);
    final none = selection.matched == 0;
    final names = selection.shown.take(8).map((d) => d.displayName).join(' · ');

    return Container(
      margin: EdgeInsets.only(top: t.space.xs),
      padding: EdgeInsets.all(t.space.sm),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: BorderRadius.circular(t.radius.sm),
        border: Border.all(
          // A card that will be empty is the one thing here worth colouring.
          color: none ? t.accent.warn : t.stroke.hairline,
          width: t.stroke.width,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            none
                ? 'No devices match'
                : selection.truncated
                    ? '${selection.matched} devices · showing '
                        'first ${selection.shown.length}'
                    : '${selection.matched} '
                        '${selection.matched == 1 ? "device" : "devices"}',
            style: t.text.bodySmallStyle.copyWith(
                color: none ? t.accent.warn : t.surface.onBase,
                fontFeatures: t.numericFontFeatures),
          ),
          if (none)
            Padding(
              padding: EdgeInsets.only(top: t.space.xs / 2),
              child: Text(
                'This card will be blank on the page.',
                style: t.text.captionStyle
                    .copyWith(color: t.surface.onBaseMuted, height: 1.35),
              ),
            )
          else ...[
            SizedBox(height: t.space.xs / 2),
            Text(
              names,
              style: t.text.captionStyle
                  .copyWith(color: t.surface.onBaseMuted, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

/// The card's picture.
///
/// It was a bare address field, with a note saying an upload could replace it
/// "without the stored shape changing". That day arrived and the note held:
/// the field still stores a string, [AssetField] just gives you a way to make
/// one.
class _ImageField extends StatelessWidget {
  const _ImageField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => AssetField(
        value: value,
        onChanged: onChanged,
        label: 'Picture',
      );
}

/// A row of choices, small enough to sit in a 340px pane.
class _StyleChoice extends StatelessWidget {
  const _StyleChoice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<({String key, String label})> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.text.bodyStyle.copyWith(color: t.surface.onBase)),
        SizedBox(height: t.space.xs),
        Wrap(
          spacing: t.space.xs,
          runSpacing: t.space.xs,
          children: [
            for (final option in options)
              Semantics(
                button: true,
                selected: option.key == value,
                child: GestureDetector(
                  onTap: () => onChanged(option.key),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: t.space.sm, vertical: t.space.xs / 2),
                    decoration: BoxDecoration(
                      color: option.key == value ? t.surface.raised : null,
                      borderRadius: BorderRadius.circular(t.radius.pill),
                      border: Border.all(
                        color: option.key == value
                            ? t.accent.active
                            : t.stroke.hairline,
                        width: t.stroke.width,
                      ),
                    ),
                    child: Text(option.label,
                        style: t.text.captionStyle.copyWith(
                            color: option.key == value
                                ? t.surface.onBase
                                : t.surface.onBaseMuted)),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Blur, 0–20, in whole steps.
///
/// Steps rather than a continuous drag: nobody can tell 11 from 12, and a
/// stored 11.437 is a number that came from a pixel rather than a decision.
class _StyleSlider extends StatelessWidget {
  const _StyleSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    this.min = 0,
    this.suffix = '',
  });

  final String label;
  final double value;
  final double max;

  /// Sliders here have started at zero until now. A turn goes both ways, and a
  /// control that could only turn one way would make the other direction a
  /// journey through 359 degrees.
  final double min;

  /// A unit on the readout. Without it a slider reading 40 says nothing about
  /// whether that is degrees, percent, or pixels.
  final String suffix;

  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label,
              style: t.text.bodyStyle.copyWith(color: t.surface.onBase)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).round(),
            label: '${value.round()}$suffix',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 32,
          child: Text('${value.round()}$suffix',
              textAlign: TextAlign.right,
              style: t.text.captionStyle.copyWith(
                  color: t.surface.onBaseMuted,
                  fontFeatures: t.numericFontFeatures)),
        ),
      ],
    );
  }
}

/// Card types whose contents are a device selection.
///
/// The same set `_Preview` counts, and for the same reason: these are the cards
/// where "what is in it" is a question with an answer.
bool _selects(String type) => const {
      'device_grid',
      'device_list',
      'device_tile',
      'media_player',
    }.contains(type);

/// The card's name, as a labelled field.
///
/// It was an unlabelled `TextField` styled to look exactly like the heading it
/// replaced — which meant that a card could be renamed and nobody knew. The
/// live page grew two cards both called "One device" and one called "Device
/// list", none of them renamed, because nothing on screen said the name was
/// yours to change. An affordance that looks like static text is not an
/// affordance.
class _NameField extends StatefulWidget {
  const _NameField({
    super.key,
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  final String value;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NAME',
              style:
                  t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.xs),
          TextField(
            controller: _controller,
            style: t.text.bodyStyle.copyWith(color: t.surface.onBase),
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              // An untitled card shows what it is, greyed, rather than an
              // empty box.
              hintText: widget.hint,
              hintStyle:
                  t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Background and border, as two switches.
///
/// Deliberately not a preset list ("Boxed / Plain / Outline"). The two
/// properties are independent and each maps to one thing you can see, so a
/// preset would be a name to learn for a combination you can already read off
/// the switches — and the interesting one, a card with a border and no fill, is

/// What the house is driving on this element.
///
/// The panel builds itself from [WidgetDescriptor.bindable], so an element that
/// has thought about what a reading would mean for it gets an editor for free
/// and one that has not offers nothing — rather than offering a property that
/// quietly does nothing once bound.
///
/// Every property is listed, bound or not. A dashed row saying a colour COULD
/// follow a device is the whole discoverability of the feature; a list that
/// showed only what was already wired would leave the capability invisible to
/// anyone who had not been told.
class _DataSection extends ConsumerWidget {
  const _DataSection({
    required this.descriptor,
    required this.config,
    required this.onChanged,
  });

  final WidgetDescriptor descriptor;
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value ?? const <DeviceState>[];
    final bindings = Bindings.fromConfig(config);

    void write(Bindings next) => onChanged(next.toConfig(config));

    return Padding(
      padding: EdgeInsets.only(top: t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'FOLLOWS THE HOUSE',
            style: t.text.overlineStyle.copyWith(color: t.accent.primary),
          ),
          SizedBox(height: t.space.xs),
          for (final p in descriptor.bindable)
            _BindingRow(
              key: ValueKey('bind-${p.name}'),
              property: p,
              binding: bindings.forProperty(p.name),
              devices: devices,
              onChanged: (b) => write(bindings.with_(b)),
              onRemove: () => write(bindings.without(p.name)),
            ),
          if (devices.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: t.space.xs),
              child: Text(
                'No devices here yet, so there is nothing to follow.',
                style: t.text.captionStyle
                    .copyWith(color: t.surface.onBaseMuted, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

class _BindingRow extends StatelessWidget {
  const _BindingRow({
    super.key,
    required this.property,
    required this.binding,
    required this.devices,
    required this.onChanged,
    required this.onRemove,
  });

  final BindableProperty property;
  final PropertyBinding? binding;
  final List<DeviceState> devices;
  final ValueChanged<PropertyBinding> onChanged;
  final VoidCallback onRemove;

  /// What a device is actually reporting, not what its schema says it might.
  ///
  /// An attribute a device has never sent is one a binding could only ever
  /// answer null about, and offering it would be offering a wire to nowhere.
  static List<String> _attributes(DeviceState d) =>
      d.state.keys.toList()..sort();

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final b = binding;

    if (b == null) {
      return Padding(
        padding: EdgeInsets.only(bottom: t.space.xs),
        child: GestureDetector(
          onTap: devices.isEmpty ? null : () => onChanged(_seed()),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: t.space.sm, vertical: t.space.sm),
            decoration: BoxDecoration(
              border: Border.all(
                color: t.accent.primary.withValues(alpha: .30),
                style: BorderStyle.solid,
              ),
              borderRadius: t.radius.smR,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 54,
                  child: Text(property.label,
                      style: t.text.captionStyle
                          .copyWith(color: t.surface.onBaseMuted)),
                ),
                Expanded(
                  child: Text(
                    devices.isEmpty ? 'nothing to follow' : 'follow a device…',
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted),
                  ),
                ),
                Icon(Icons.add, size: 13, color: t.accent.primary),
              ],
            ),
          ),
        ),
      );
    }

    final device = devices
        .where((d) => d.id == b.deviceId)
        .cast<DeviceState?>()
        .firstOrNull;

    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: Container(
        padding: EdgeInsets.all(t.space.sm),
        decoration: BoxDecoration(
          color: t.accent.primary.withValues(alpha: .06),
          border: Border.all(color: t.accent.primary.withValues(alpha: .28)),
          borderRadius: t.radius.smR,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 54,
                  child: Text(property.label,
                      style: t.text.captionStyle
                          .copyWith(color: t.accent.primary)),
                ),
                Expanded(
                  child: Text(
                    device?.name ?? b.deviceId,
                    style:
                        t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  // Keyed: `Icons.close` appears several times in this panel,
                  // including the one that shuts it, so a finder by icon would
                  // reach for whichever came first.
                  key: ValueKey('unbind-${property.name}'),
                  onTap: onRemove,
                  child:
                      Icon(Icons.close, size: 13, color: t.surface.onBaseMuted),
                ),
              ],
            ),
            SizedBox(height: t.space.xs),
            _Picker(
              label: 'Device',
              value: b.deviceId,
              options: [
                for (final d in devices) (key: d.id, label: d.name ?? d.id),
              ],
              // Changing the device clears the attribute: it belonged to the
              // device that was chosen, and keeping it would name a reading the
              // new one does not send — a wire that answers null forever with
              // nothing on screen saying why.
              onChanged: (v) {
                final next = devices.firstWhere((d) => d.id == v);
                onChanged(b.copyWith(
                  deviceId: v,
                  key: _attributes(next).firstOrNull ?? '',
                ));
              },
            ),
            if (device != null)
              _Picker(
                label: 'Reading',
                value: b.key,
                options: [
                  for (final a in _attributes(device)) (key: a, label: a),
                ],
                onChanged: (v) => onChanged(b.copyWith(key: v)),
              ),
            if (property.kind == BindKind.look)
              _LookTable(binding: b, onChanged: onChanged)
            else
              _RangeFields(
                binding: b,
                unit: property.unit,
                onChanged: onChanged,
              ),
          ],
        ),
      ),
    );
  }

  /// A new binding that already does something.
  ///
  /// Seeded with the first device and its first reading, and — for a colour —
  /// with an on/off pair, because a binding that changed nothing would look
  /// like the row had not worked.
  PropertyBinding _seed() {
    final d = devices.first;
    return PropertyBinding(
      property: property.name,
      deviceId: d.id,
      key: _attributes(d).firstOrNull ?? '',
      map: property.kind == BindKind.look
          ? const {'true': 'accent', 'false': 'muted'}
          : const {},
    );
  }
}

/// The value → look table, for the readings that are not numbers.
class _LookTable extends StatelessWidget {
  const _LookTable({required this.binding, required this.onChanged});

  final PropertyBinding binding;
  final ValueChanged<PropertyBinding> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final on = binding.map['true'];
    final off = binding.map['false'];

    Widget swatch(String forValue, String? ink) => GestureDetector(
          onTap: () {
            // Round the palette rather than opening a picker: two taps to try
            // every colour beats a dialog for a choice with six answers.
            final keys = [for (final i in inkColours) i.key];
            final at = ink == null ? -1 : keys.indexOf(ink);
            final next = keys[(at + 1) % keys.length];
            onChanged(binding.copyWith(map: {...binding.map, forValue: next}));
          },
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: resolveInk(t, ink) ?? t.surface.sunken,
              borderRadius: t.radius.xsR,
              border: Border.all(color: t.stroke.hairline),
            ),
          ),
        );

    return Padding(
      padding: EdgeInsets.only(top: t.space.xs),
      child: Row(
        children: [
          Text('on',
              style:
                  t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(width: t.space.xs),
          swatch('true', on),
          SizedBox(width: t.space.md),
          Text('off',
              style:
                  t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(width: t.space.xs),
          swatch('false', off),
        ],
      ),
    );
  }
}

/// The four range bounds, which are all four or none.
class _RangeFields extends StatelessWidget {
  const _RangeFields({
    required this.binding,
    required this.unit,
    required this.onChanged,
  });

  final PropertyBinding binding;
  final String? unit;
  final ValueChanged<PropertyBinding> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    Widget field(String label, double? value, ValueChanged<double?> set) =>
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: t.space.xs),
            child: TextFormField(
              key: ValueKey('range-$label-${binding.property}'),
              initialValue: value == null ? '' : '$value',
              style: t.text.captionStyle.copyWith(color: t.surface.onBase),
              decoration: InputDecoration(
                isDense: true,
                labelText: label,
                labelStyle:
                    t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
                border: const OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: t.space.xs),
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) => set(double.tryParse(v)),
            ),
          ),
        );

    return Padding(
      padding: EdgeInsets.only(top: t.space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            field('from', binding.inFrom,
                (v) => onChanged(binding.copyWith(inFrom: v))),
            field('to', binding.inTo,
                (v) => onChanged(binding.copyWith(inTo: v))),
          ]),
          SizedBox(height: t.space.xs),
          Row(children: [
            field('→', binding.outFrom,
                (v) => onChanged(binding.copyWith(outFrom: v))),
            field('→', binding.outTo,
                (v) => onChanged(binding.copyWith(outTo: v))),
          ]),
          SizedBox(height: t.space.xs),
          Text(
            binding.hasRange
                ? 'Mapped${unit == null ? '' : ' to $unit'}.'
                : 'All four, or none — three of them is how a dial quietly '
                    'reads nothing.',
            style: t.text.captionStyle.copyWith(
              color: binding.hasRange ? t.surface.onBaseMuted : t.accent.warn,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// The compact label-over-chips row the rest of this panel uses.
class _Picker extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<({String key, String label})> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: _StyleChoice(
          label: label,
          value: value,
          options: options,
          onChanged: onChanged,
        ),
      );
}

/// "When the house says this, look like that."
///
/// A deliberately smaller control than the rules' `DeviceConditionPicker`, and
/// not a reuse of it. That picker covers the whole condition vocabulary — time
/// windows, hub variables, Rhai — and a card answers **false** to every one of
/// those, so offering them here would be a menu of things that quietly do
/// nothing. This offers exactly what `card_condition.dart` can evaluate: a
/// device, one of its attributes, a comparison, and a value.
///
/// The style side is a tint and nothing else, for now. It is what the two
/// motivating cases need — *"when this door is open, this card is red"* and
/// *"when it is unavailable, dim it"* — and a variant is a patch, so widening
/// it later adds keys rather than changing what the existing ones mean.
class _VariantsSection extends ConsumerWidget {
  const _VariantsSection({required this.style, required this.onChanged});

  final CardStyle style;
  final ValueChanged<CardStyle> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value ?? const <DeviceState>[];

    return Padding(
      padding: EdgeInsets.only(top: t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('WHEN',
              style:
                  t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.xs),
          if (style.variants.isEmpty)
            Text(
              'This card looks the same whatever the house is doing.',
              style: t.text.captionStyle
                  .copyWith(color: t.surface.onBaseMuted, height: 1.4),
            ),
          for (var i = 0; i < style.variants.length; i++)
            _VariantRow(
              key: ValueKey('variant-$i'),
              variant: style.variants[i],
              devices: devices,
              // The order is the author's and the first match wins, so the
              // position of a row is a decision rather than a detail — which is
              // why one is numbered rather than merely listed.
              index: i,
              onChanged: (next) => onChanged(style.copyWith(variants: [
                for (var j = 0; j < style.variants.length; j++)
                  if (j == i) next else style.variants[j],
              ])),
              onRemove: () => onChanged(style.copyWith(variants: [
                for (var j = 0; j < style.variants.length; j++)
                  if (j != i) style.variants[j],
              ])),
            ),
          SizedBox(height: t.space.xs),
          OutlinedButton(
            onPressed: devices.isEmpty
                ? null
                : () => onChanged(style.copyWith(variants: [
                      ...style.variants,
                      StyleVariant(
                        when: CardCondition(
                          tag: 'DeviceState',
                          deviceId: devices.first.id,
                          attribute: _attributesOf(devices.first).firstOrNull,
                          value: true,
                        ),
                        // Alert rather than the card's own colour: a variant
                        // that changed nothing would look like the button had
                        // not worked.
                        style: const {'tint': 'danger'},
                      ),
                    ])),
            child: const Text('Add a state'),
          ),
        ],
      ),
    );
  }
}

/// The attributes of a device worth offering, most useful first.
///
/// Straight from what the device is actually reporting rather than from its
/// schema: a card is styled against what arrives, and an attribute a device has
/// never sent is one a condition could only ever answer false about.
List<String> _attributesOf(DeviceState device) =>
    device.state.keys.toList()..sort();

class _VariantRow extends StatelessWidget {
  const _VariantRow({
    super.key,
    required this.variant,
    required this.devices,
    required this.index,
    required this.onChanged,
    required this.onRemove,
  });

  final StyleVariant variant;
  final List<DeviceState> devices;
  final int index;
  final ValueChanged<StyleVariant> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final when = variant.when;
    final device = devices
        .where((d) => d.id == when.deviceId)
        .cast<DeviceState?>()
        .firstOrNull;

    void write({
      String? deviceId,
      String? attribute,
      String? op,
      Object? value,
      String? tint,
    }) =>
        onChanged(StyleVariant(
          when: CardCondition(
            tag: 'DeviceState',
            deviceId: deviceId ?? when.deviceId,
            attribute: attribute ?? when.attribute,
            op: op ?? when.op,
            value: value ?? when.value,
          ),
          style:
              tint == null ? variant.style : {...variant.style, 'tint': tint},
        ));

    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${index + 1}.',
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted)),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 14),
                tooltip: 'Remove this state',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          _RowChoice(
            label: 'Device',
            value: when.deviceId ?? '',
            options: [
              for (final d in devices) (key: d.id, label: d.name ?? d.id),
            ],
            // Changing the device clears the attribute: the attribute belonged
            // to the device that was chosen, and keeping it would name one the
            // new device does not report.
            onChanged: (v) => write(
              deviceId: v,
              attribute: _attributesOf(
                    devices.firstWhere((d) => d.id == v),
                  ).firstOrNull ??
                  '',
            ),
          ),
          if (device != null)
            _RowChoice(
              label: 'Is',
              value: when.attribute ?? '',
              options: [
                for (final a in _attributesOf(device)) (key: a, label: a),
              ],
              onChanged: (v) => write(attribute: v),
            ),
          _RowChoice(
            label: 'Which',
            value: when.op,
            options: const [
              (key: 'Eq', label: 'is'),
              (key: 'Ne', label: 'is not'),
              (key: 'Gt', label: 'is above'),
              (key: 'Lt', label: 'is below'),
            ],
            onChanged: (v) => write(op: v),
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: t.space.xs),
            child: TextFormField(
              key: ValueKey('variant-value-$index-${when.deviceId}'),
              initialValue: '${when.value ?? ''}',
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Value',
              ),
              // Kept as typed. `true`, `21.5` and `open` are all legitimate
              // answers, and the condition itself already knows how to compare
              // a word against a bool and a number written as a string — so
              // guessing a type here would be a second, worse copy of that.
              onChanged: (v) => write(value: v),
            ),
          ),
          _RowChoice(
            label: 'Then',
            value: variant.style['tint'] as String? ?? 'danger',
            options: [
              for (final tint in cardTints) (key: tint.key, label: tint.label)
            ],
            onChanged: (v) => write(tint: v),
          ),
        ],
      ),
    );
  }
}

/// A compact label-over-chips row, the same shape [_StyleChoice] uses.
class _RowChoice extends StatelessWidget {
  const _RowChoice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<({String key, String label})> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: _StyleChoice(
          label: label,
          value: value,
          options: options,
          onChanged: onChanged,
        ),
      );
}

/// The card's transform: how far it is turned, and how far it has faded.
///
/// Separate from STYLE because the two are stored in different places and that
/// difference is real rather than incidental. Style is the *element* — it moves
/// with the card to every breakpoint, in its config. A transform is the
/// *arrangement* — it lives on the placement, so a card turned on the desktop
/// is not turned on the phone, which is the only reading that could be right:
/// eight degrees on a wide canvas is a composition, and the same card
/// full-width on a phone is a mistake.
///
/// Both are paint. Neither moves the card out of the cells it occupies, so
/// turning something never reflows the page around it — see
/// `docs/dashboard-layout.md`.

/// X, Y, W, H — typed, not only dragged.
///
/// **The gap this closes is the difference between a layout tool and a design
/// tool.** Everything about where a card sits could be *dragged* and nothing
/// about it could be *said*: two cards could be nudged until they looked
/// aligned and be a pixel apart, and there was no way to find out, let alone
/// fix it. Every drawing application since the first has had these four boxes
/// in the corner of its inspector for that reason.
///
/// It appears only for a composed element — one with a rectangle of its own. A
/// card packed by the grid engine has no x it could be told, because the engine
/// decides; offering four fields that silently did nothing would be worse than
/// offering none.

/// Every key on this element, whether or not anyone drew a control for it.
///
/// **The editor never hides a key it does not understand.** Three fields core
/// validates had no control here at all — an event feed's type and device
/// filters, a chart's row cap — which means opening such a card, changing
/// anything, and saving silently dropped settings a person had made elsewhere.
/// That is not a bug in three widgets; it is what happens whenever the form and
/// the document disagree about what a card holds, and the form is the only way
/// in.
///
/// So this is the way in for everything else. A config a plugin card wrote, a
/// key a newer client added, a field somebody typed by hand: all here, all
/// editable, none of them lost because this version of this app has not caught
/// up.
///
/// Folded shut by default. It is a hatch, not a panel — the drawn controls
/// above are how you are meant to work, and a raw key list open by default
/// would say otherwise.

/// What this element does when you touch it.
///
/// Offered for **every** element, because an action belongs to all of them or
/// to none — that is the whole finding behind `on_tap` being a property rather
/// than a Button element. A shape you styled, a label, an icon, a photograph of
/// a room: any of them can run a scene.
///
/// Nothing here reaches the rule engine. Each action is a call the app already
/// makes somewhere else; see `features/dashboard/tappable.dart`.
class _TapSection extends ConsumerWidget {
  const _TapSection({required this.config, required this.onChanged});

  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  void _write(TapAction? action) =>
      onChanged(TapAction.toConfig(config, action));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final action = TapAction.fromConfig(config);

    return Padding(
      padding: EdgeInsets.only(top: t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('WHEN TAPPED',
                style: t.text.overlineStyle
                    .copyWith(color: t.surface.onBaseMuted)),
            const Spacer(),
            if (action != null)
              InkWell(
                key: const ValueKey('clear-on-tap'),
                onTap: () => _write(null),
                child: Padding(
                  padding: EdgeInsets.all(t.space.xs),
                  child:
                      Icon(Icons.close, size: 14, color: t.surface.onBaseMuted),
                ),
              ),
          ]),
          SizedBox(height: t.space.xs),
          _RowChoice(
            label: 'Does',
            value: action?.action.wire ?? '',
            options: const [
              (key: '', label: 'Nothing'),
              (key: 'scene', label: 'Run a scene'),
              (key: 'mode', label: 'Set a mode'),
              (key: 'set', label: 'Set a device'),
              (key: 'page', label: 'Go to a page'),
            ],
            onChanged: (v) {
              final kind = TapDo.fromWire(v);
              if (kind == null) return _write(null);
              _write(action == null
                  ? TapAction(action: kind)
                  : action.with_(action: kind));
            },
          ),
          if (action != null) ...[
            SizedBox(height: t.space.xs),
            _TapTarget(
              action: action,
              onChanged: (next) => _write(next),
            ),
            // Said, rather than left to be discovered by tapping something on a
            // wall. A half-set action is what a control looks like while it is
            // being built, not an error — but it must not look finished.
            if (!action.isComplete)
              Padding(
                padding: EdgeInsets.only(top: t.space.xs),
                child: Text(
                  action.action == TapDo.set
                      ? 'Pick a device and one of its settings, or this does '
                          'nothing.'
                      : 'Pick one, or this does nothing.',
                  style: t.text.captionStyle.copyWith(color: t.accent.warn),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// The thing an action acts on: a scene, a mode, a device, or a page.
class _TapTarget extends ConsumerWidget {
  const _TapTarget({required this.action, required this.onChanged});

  final TapAction action;
  final ValueChanged<TapAction> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    switch (action.action) {
      case TapDo.scene:
        // Both kinds together, because to whoever is drawing the page they are
        // the same thing — only the code that sends knows the difference.
        final native = ref.watch(scenesProvider).value ?? const [];
        final devices = ref.watch(devicesProvider).value ?? const [];
        final choices = <({String id, String label})>[
          for (final s in native) (id: s.id, label: s.name),
          for (final d in devices)
            if (isSceneDevice(d)) (id: d.id, label: d.displayName),
        ]..sort(
            (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
        return _Picker(
          label: 'Scene',
          value: action.targetId ?? '',
          options: choices.map((c) => (key: c.id, label: c.label)).toList(),
          onChanged: (v) => onChanged(action.with_(targetId: v)),
        );
      case TapDo.mode:
        final modes = ref.watch(modesProvider).value ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Picker(
              label: 'Mode',
              value: action.targetId ?? '',
              options: [
                for (final m in modes)
                  (key: m.id, label: m.name ?? humanize(m.id))
              ],
              onChanged: (v) => onChanged(action.with_(targetId: v)),
            ),
            SizedBox(height: t.space.xs),
            _RowChoice(
              label: 'To',
              value: action.value is bool
                  ? (action.value! as bool ? 'on' : 'off')
                  : 'flip',
              options: const [
                (key: 'flip', label: 'The other way'),
                (key: 'on', label: 'On'),
                (key: 'off', label: 'Off'),
              ],
              onChanged: (v) => onChanged(v == 'flip'
                  ? action.with_(clearValue: true)
                  : action.with_(value: v == 'on')),
            ),
          ],
        );
      case TapDo.set:
        final devices = ref.watch(devicesProvider).value ?? const [];
        final device =
            devices.where((d) => d.id == action.targetId).firstOrNull;
        // Only what the plugin registered, and only booleans while the action
        // flips: a tap that "toggles" a brightness has no second state to go
        // to. Same rule as the switch — see `attribute_policy.dart`.
        final offered = <String>[
          for (final e in (device?.schema?.writable ?? const {}).entries)
            if (e.value.kind == AttributeKind.bool_) e.key,
        ]..sort();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Picker(
              label: 'Device',
              value: action.targetId ?? '',
              options: [
                for (final d in devices)
                  if (!isSceneDevice(d)) (key: d.id, label: d.displayName)
              ],
              onChanged: (v) => onChanged(action.with_(targetId: v)),
            ),
            SizedBox(height: t.space.xs),
            if (device == null)
              Text('Pick a device first.',
                  style: t.text.captionStyle
                      .copyWith(color: t.surface.onBaseMuted))
            else if (offered.isEmpty)
              Text(
                '${device.displayName} accepts no on/off writes, so a tap '
                'cannot set it.',
                style:
                    t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
              )
            else
              _Picker(
                label: 'Flips',
                value: action.attribute ?? '',
                options: [
                  for (final a in offered) (key: a, label: humanize(a))
                ],
                onChanged: (v) => onChanged(action.with_(attribute: v)),
              ),
          ],
        );
      case TapDo.page:
        final pages = ref.watch(dashboardsProvider).value ?? const [];
        return _Picker(
          label: 'Page',
          value: action.targetId ?? '',
          options: [for (final d in pages) (key: d.id, label: d.name)],
          onChanged: (v) => onChanged(action.with_(targetId: v)),
        );
    }
  }
}

class _AllPropertiesSection extends StatefulWidget {
  const _AllPropertiesSection({required this.config, required this.onChanged});

  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_AllPropertiesSection> createState() => _AllPropertiesSectionState();
}

class _AllPropertiesSectionState extends State<_AllPropertiesSection> {
  bool _open = false;
  String _filter = '';

  /// A typed value back into the config, keeping the type it had.
  ///
  /// A `limit` that was 20 must not come back as `"20"`: core validates it as
  /// an integer and would refuse the save, having accepted the card until
  /// somebody opened this list. Text is the fallback, not the rule.
  void _write(String key, String raw) {
    final was = widget.config[key];
    final text = raw.trim();
    final Object? value;
    if (was is bool) {
      value = text.toLowerCase() == 'true';
    } else if (was is int) {
      value = int.tryParse(text) ?? was;
    } else if (was is double) {
      value = double.tryParse(text) ?? was;
    } else if (was is List || was is Map) {
      // Structured values are shown and not edited here. A comma-splitting
      // guess at a device id list is how you lose one.
      return;
    } else {
      value = text;
    }
    widget.onChanged({...widget.config, key: value});
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final keys = widget.config.keys.toList()..sort();
    final shown = _filter.isEmpty
        ? keys
        : keys.where((k) => k.toLowerCase().contains(_filter)).toList();

    return Padding(
      padding: EdgeInsets.only(top: t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: t.space.xs),
              child: Row(children: [
                Text('ALL PROPERTIES',
                    style: t.text.overlineStyle
                        .copyWith(color: t.surface.onBaseMuted)),
                SizedBox(width: t.space.xs),
                Text('${keys.length}',
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted)),
                const Spacer(),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: t.surface.onBaseMuted,
                ),
              ]),
            ),
          ),
          if (_open) ...[
            if (keys.length > 8)
              Padding(
                padding: EdgeInsets.only(bottom: t.space.xs),
                child: TextField(
                  onChanged: (v) =>
                      setState(() => _filter = v.trim().toLowerCase()),
                  style:
                      t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Filter',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            if (shown.isEmpty)
              Text(
                keys.isEmpty ? 'Nothing set on this one yet.' : 'No key here.',
                style:
                    t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
              )
            else
              for (final key in shown)
                _PropertyRow(
                  name: key,
                  value: widget.config[key],
                  onChanged: (v) => _write(key, v),
                ),
          ],
        ],
      ),
    );
  }
}

class _PropertyRow extends StatelessWidget {
  const _PropertyRow({
    required this.name,
    required this.value,
    required this.onChanged,
  });

  final String name;
  final Object? value;
  final ValueChanged<String> onChanged;

  /// Structured values are read-only here — see `_write`.
  bool get _editable => value is! List && value is! Map;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final text = switch (value) {
      null => '',
      final List l => '${l.length} items',
      final Map m => '${m.length} keys',
      final other => '$other',
    };
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: t.text.captionStyle.copyWith(
                color: t.surface.onBaseMuted,
                fontFamily: t.text.monoFamily,
              ),
            ),
          ),
          Expanded(
            child: _editable
                ? TextFormField(
                    key: ValueKey('prop-$name-$text'),
                    initialValue: text,
                    onFieldSubmitted: onChanged,
                    // Commits on blur too, the way the position boxes do: a
                    // value you typed and clicked away from was still typed.
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    style: t.text.bodySmallStyle.copyWith(
                      color: t.surface.onBase,
                      fontFamily: t.text.monoFamily,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: t.space.sm, vertical: t.space.xs),
                    ),
                  )
                : Text(
                    text,
                    style: t.text.captionStyle.copyWith(
                      color: t.surface.onBaseMuted,
                      fontFamily: t.text.monoFamily,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PositionSection extends StatelessWidget {
  const _PositionSection({
    required this.rect,
    required this.rotation,
    required this.onRect,
    required this.onRotate,
  });

  final DashboardRect rect;
  final double? rotation;
  final ValueChanged<DashboardRect> onRect;
  final ValueChanged<double?> onRotate;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('POSITION',
              style:
                  t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.xs),
          Row(children: [
            Expanded(
              child: _NumberBox(
                label: 'X',
                value: rect.x,
                onChanged: (v) => onRect(rect.copyWith(x: v)),
              ),
            ),
            SizedBox(width: t.space.xs),
            Expanded(
              child: _NumberBox(
                label: 'Y',
                value: rect.y,
                onChanged: (v) => onRect(rect.copyWith(y: v)),
              ),
            ),
          ]),
          SizedBox(height: t.space.xs),
          Row(children: [
            Expanded(
              child: _NumberBox(
                label: 'W',
                value: rect.w,
                // Never zero. A rectangle with no width is a card you cannot
                // see and cannot click, so it cannot be selected to be fixed —
                // the one edit here that could lose somebody their work.
                min: 1,
                onChanged: (v) => onRect(rect.copyWith(w: v)),
              ),
            ),
            SizedBox(width: t.space.xs),
            Expanded(
              child: _NumberBox(
                label: 'H',
                value: rect.h,
                min: 1,
                onChanged: (v) => onRect(rect.copyWith(h: v)),
              ),
            ),
          ]),
          SizedBox(height: t.space.xs),
          Row(children: [
            Expanded(
              child: _NumberBox(
                label: '∠',
                value: rotation ?? 0,
                suffix: '°',
                // Cleared back to none rather than to zero: a card at exactly
                // 0° and a card nobody turned are the same picture, and only
                // one of them adds a key to the document.
                onChanged: (v) => onRotate(v == 0 ? null : v),
              ),
            ),
            SizedBox(width: t.space.xs),
            const Expanded(child: SizedBox()),
          ]),
        ],
      ),
    );
  }
}

/// One number you can type.
///
/// Commits on Enter and on losing focus, never per keystroke: a field that
/// applied every character would move the card to x=1 on the way to typing 120,
/// and each of those is an undo entry.
class _NumberBox extends StatefulWidget {
  const _NumberBox({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min,
    this.suffix,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double? min;
  final String? suffix;

  @override
  State<_NumberBox> createState() => _NumberBoxState();
}

class _NumberBoxState extends State<_NumberBox> {
  late final TextEditingController _controller =
      TextEditingController(text: _show(widget.value));
  late final FocusNode _focus = FocusNode()..addListener(_onFocus);

  @override
  void didUpdateWidget(covariant _NumberBox old) {
    super.didUpdateWidget(old);
    // Dragged on the canvas while the field is on screen: follow it, unless
    // somebody is mid-edit, where overwriting what they are typing is worse
    // than being briefly out of date.
    if (widget.value != old.value && !_focus.hasFocus) {
      _controller.text = _show(widget.value);
      _sent = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  /// The value this box last sent, so pressing Enter and then clicking away
  /// is one edit rather than two. Both gestures commit, deliberately — a
  /// number you typed and clicked away from was still typed — and without this
  /// the second would send the same rectangle again and take an undo step with
  /// it.
  late double _sent = widget.value;

  void _commit() {
    final typed = double.tryParse(_controller.text.trim());
    // Unparseable goes back to what it was rather than to zero. "12o" is a
    // typo, not a request to move the card to the origin.
    if (typed == null) {
      _controller.text = _show(widget.value);
      return;
    }
    final next = widget.min != null && typed < widget.min!
        ? widget.min!
        : typed.roundToDouble();
    _controller.text = _show(next);
    if (next == _sent) return;
    _sent = next;
    widget.onChanged(next);
  }

  static String _show(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return TextField(
      controller: _controller,
      focusNode: _focus,
      onSubmitted: (_) => _commit(),
      keyboardType: const TextInputType.numberWithOptions(signed: true),
      style: t.text.bodySmallStyle.copyWith(
        color: t.surface.onBase,
        fontFeatures: t.numericFontFeatures,
      ),
      decoration: InputDecoration(
        isDense: true,
        prefixText: '${widget.label}  ',
        prefixStyle: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
        suffixText: widget.suffix,
        suffixStyle: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
        border: const OutlineInputBorder(),
        contentPadding:
            EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.sm),
      ),
    );
  }
}

class _TransformSection extends StatelessWidget {
  const _TransformSection({
    required this.rotation,
    required this.opacity,
    required this.onRotate,
    required this.onFade,
  });

  final double? rotation;
  final double? opacity;
  final ValueChanged<double?> onRotate;
  final ValueChanged<double?> onFade;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('TRANSFORM',
              style:
                  t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.xs),
          _StyleSlider(
            label: 'Turn',
            value: rotation ?? 0,
            // Half a turn either way reaches every angle. Core allows a whole
            // one, which a slider would spend half its length repeating.
            min: -180,
            max: 180,
            suffix: '°',
            // Back to none rather than to zero: a card at exactly 0° and a card
            // nobody turned are the same picture, and only one of them adds a
            // key to the document.
            onChanged: (v) => onRotate(v == 0 ? null : v),
          ),
          SizedBox(height: t.space.xs),
          _StyleSlider(
            label: 'Fade',
            // Shown as a percentage and stored as a fraction: every renderer
            // takes a fraction, and a document storing 40 while every client
            // divided by 100 would be describing the division.
            value: opacityToControl(opacity),
            max: 100,
            suffix: '%',
            onChanged: (v) => onFade(opacityFromControl(v)),
          ),
        ],
      ),
    );
  }
}

class _StyleSection extends StatelessWidget {
  const _StyleSection({
    required this.style,
    required this.onChanged,
    required this.cardId,
  });

  final CardStyle style;
  final ValueChanged<CardStyle> onChanged;

  /// Keys the picture field, so moving the selection to another card does not
  /// leave the previous card's address sitting in it.
  final String cardId;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('STYLE',
              style:
                  t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.xs),
          _StyleSwitch(
            label: 'Background',
            value: style.filled,
            onChanged: (v) => onChanged(style.copyWith(filled: v)),
          ),
          _StyleSwitch(
            label: 'Border',
            value: style.bordered,
            onChanged: (v) => onChanged(style.copyWith(bordered: v)),
          ),
          _StyleSwitch(
            label: 'Title',
            value: style.titled,
            onChanged: (v) => onChanged(style.copyWith(titled: v)),
          ),
          if (style.filled) ...[
            SizedBox(height: t.space.xs),
            _StyleChoice(
              label: 'Colour',
              value: style.tint ?? 'raised',
              options: [
                for (final tint in cardTints) (key: tint.key, label: tint.label)
              ],
              onChanged: (v) =>
                  onChanged(style.copyWith(tint: v == 'raised' ? null : v)),
            ),
          ],
          SizedBox(height: t.space.xs),
          _StyleChoice(
            label: 'Corners',
            value: style.corner ?? 'md',
            options: cardCorners,
            onChanged: (v) =>
                onChanged(style.copyWith(corner: v == 'md' ? null : v)),
          ),
          SizedBox(height: t.space.xs),
          _StyleSlider(
            label: 'Blur',
            value: style.blur,
            max: 20,
            onChanged: (v) => onChanged(style.copyWith(blur: v)),
          ),
          SizedBox(height: t.space.xs),
          _ImageField(
            key: ValueKey('card-image-$cardId'),
            value: style.image ?? '',
            onChanged: (v) =>
                onChanged(style.copyWith(image: v.isEmpty ? null : v)),
          ),
          if ((style.image ?? '').isNotEmpty) ...[
            SizedBox(height: t.space.xs),
            _StyleChoice(
              label: 'Picture',
              value: style.imageFit ?? 'cover',
              options: const [
                (key: 'cover', label: 'Fill'),
                (key: 'contain', label: 'Fit'),
                (key: 'fill', label: 'Stretch'),
              ],
              onChanged: (v) =>
                  onChanged(style.copyWith(imageFit: v == 'cover' ? null : v)),
            ),
            _StyleSlider(
              label: 'Fade',
              value: style.imageOpacity * 100,
              max: 100,
              onChanged: (v) =>
                  onChanged(style.copyWith(imageOpacity: v / 100)),
            ),
          ],
          if (!style.titled)
            Text(
              'The name still labels it here and in the layers strip — it just '
              'is not drawn on the card.',
              style: t.text.captionStyle
                  .copyWith(color: t.surface.onBaseMuted, height: 1.4),
            )
          else if (style.isDefault)
            Text(
              'A card, like the others.',
              style: t.text.captionStyle
                  .copyWith(color: t.surface.onBaseMuted, height: 1.4),
            )
          else
            Text(
              style.filled
                  ? 'No outline — it sits on the page without a frame.'
                  : 'The page shows through. Useful for a heading strip or a '
                      'row of controls that should not read as a card.',
              style: t.text.captionStyle
                  .copyWith(color: t.surface.onBaseMuted, height: 1.4),
            ),
        ],
      ),
    );
  }
}

/// Where the card sits relative to the grid — and, once it is above it, where
/// it sits relative to everything else up there.
///
/// The same six moves as the card's own menu, because a right-click is where
/// you go when you already know a thing exists and a panel is where you find
/// out that it does. This one also *reports*: a card either competes for its
/// cells or floats over them, and until now nothing on screen said which
/// except the status bar, one line high, at the far bottom of the window.
///
/// The stacking row is hidden while the card is in the grid rather than
/// disabled. Grid cards cannot be underneath anything, so "bring forward" is
/// not a control that happens to be unavailable — it is a question that does
/// not apply.
class _StackSection extends StatelessWidget {
  const _StackSection({
    required this.floating,
    required this.z,
    required this.onStack,
  });

  final bool floating;
  final int z;
  final ValueChanged<StackMove> onStack;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: t.space.md),
        Row(
          children: [
            Expanded(
              child: Text('DEPTH',
                  style: t.text.overlineStyle
                      .copyWith(color: t.surface.onBaseMuted)),
            ),
            if (floating)
              Text('z$z',
                  style: t.text.captionStyle.copyWith(
                      color: t.surface.onBaseMuted,
                      fontFeatures: t.numericFontFeatures)),
          ],
        ),
        SizedBox(height: t.space.xs),
        Row(
          children: [
            for (final option in const [false, true])
              Padding(
                padding: EdgeInsets.only(right: t.space.xs),
                child: Semantics(
                  button: true,
                  selected: option == floating,
                  child: GestureDetector(
                    onTap: option == floating
                        ? null
                        : () =>
                            onStack(option ? StackMove.lift : StackMove.ground),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: t.space.sm, vertical: t.space.xs / 2),
                      decoration: BoxDecoration(
                        color: option == floating ? t.surface.raised : null,
                        borderRadius: BorderRadius.circular(t.radius.pill),
                        border: Border.all(
                          color: option == floating
                              ? t.accent.active
                              : t.stroke.hairline,
                          width: t.stroke.width,
                        ),
                      ),
                      child: Text(
                        option ? 'Floating' : 'In the grid',
                        style: t.text.captionStyle.copyWith(
                            color: option == floating
                                ? t.surface.onBase
                                : t.surface.onBaseMuted),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: t.space.xs),
        Text(
          floating
              ? 'It sits on top of the grid. Nothing pushes it and it pushes '
                  'nothing.'
              : 'It takes up its cells, and the cards around it move out of '
                  'the way.',
          style: t.text.captionStyle
              .copyWith(color: t.surface.onBaseMuted, height: 1.4),
        ),
        if (floating) ...[
          SizedBox(height: t.space.sm),
          Row(
            children: [
              for (final move in const [
                StackMove.back,
                StackMove.backward,
                StackMove.forward,
                StackMove.front,
              ])
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: t.space.xs / 2),
                    child: Tooltip(
                      message: move.label,
                      child: OutlinedButton(
                        onPressed: () => onStack(move),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: t.space.xs),
                          minimumSize: Size.zero,
                          side: BorderSide(
                              color: t.stroke.hairline, width: t.stroke.width),
                        ),
                        child: Icon(
                          switch (move) {
                            StackMove.back => Icons.vertical_align_bottom,
                            StackMove.backward => Icons.keyboard_arrow_down,
                            StackMove.forward => Icons.keyboard_arrow_up,
                            _ => Icons.vertical_align_top,
                          },
                          size: 15,
                          color: t.surface.onBase,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _StyleSwitch extends StatelessWidget {
  const _StyleSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: t.text.bodyStyle.copyWith(color: t.surface.onBase)),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
