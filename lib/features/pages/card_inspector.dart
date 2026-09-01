import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/card_condition.dart';
import '../../core/dashboard/card_style.dart';
import '../../core/dashboard/free_layer.dart';
import '../../core/dashboard/transform.dart';
import '../../core/dashboard/widget_registry.dart';
import '../../core/models/device_state.dart';
import '../../core/models/dashboard.dart';
import '../../core/providers/devices_provider.dart';
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
