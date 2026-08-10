import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/card_style.dart';
import '../../core/dashboard/widget_registry.dart';
import '../../core/models/dashboard.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/tokens.dart';
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
class CardInspector extends ConsumerWidget {
  const CardInspector({
    super.key,
    required this.model,
    required this.onChanged,
    required this.onRemove,
    required this.onClose,
    this.onRename,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      child: SingleChildScrollView(
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
                  onPressed: onClose,
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
                    style:
                        t.text.bodySmallStyle.copyWith(color: t.accent.danger),
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
                onChanged: onRename!,
              ),
            if (descriptor != null && descriptor.chrome != WidgetChrome.bare)
              _StyleSection(
                cardId: model.id,
                style: CardStyle.fromConfig(model.config),
                onChanged: (style) => onChanged(style.toConfig(model.config)),
              ),
            SizedBox(height: t.space.md),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onRemove,
                child: Text('Remove from page',
                    style: TextStyle(color: t.accent.danger)),
              ),
            ),
          ],
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

/// The card's picture, as an address.
///
/// A field rather than a file picker because there is nowhere yet to put an
/// uploaded file: core stores dashboards, not assets. A URL on the LAN works
/// today and an upload can replace this without the stored shape changing.
class _ImageField extends StatefulWidget {
  const _ImageField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_ImageField> createState() => _ImageFieldState();
}

class _ImageFieldState extends State<_ImageField> {
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
    return TextField(
      controller: _controller,
      style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
      onChanged: (s) => widget.onChanged(s.trim()),
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText: 'Picture',
        hintText: 'Image address',
        hintStyle: t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted),
      ),
    );
  }
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
  });

  final String label;
  final double value;
  final double max;
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
            value: value.clamp(0, max),
            max: max,
            divisions: max.round(),
            label: '${value.round()}',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 24,
          child: Text('${value.round()}',
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
/// the combination a three-item list would leave out.
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
