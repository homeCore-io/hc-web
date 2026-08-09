import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/card_style.dart';
import '../../core/dashboard/widget_registry.dart';
import '../../core/models/dashboard.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/tokens.dart';
import '../dashboard/builtin_cards.dart';
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
                  child: onRename == null
                      ? Text(
                          model.title.isEmpty
                              ? (descriptor?.title ?? model.type)
                              : model.title,
                          style: t.text.subtitleStyle.copyWith(
                              color: t.surface.onBase,
                              fontWeight: FontWeight.w600),
                        )
                      : _TitleField(
                          key: ValueKey('title-${model.id}'),
                          value: model.title,
                          hint: descriptor?.title ?? model.type,
                          onChanged: onRename!,
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
            ],
            // Style is offered only where there is a card to un-draw. A
            // heading, a rule and a spacer have no surface at all, so a
            // "background" switch on one would be a control with nothing
            // behind it.
            if (descriptor != null && descriptor.chrome != WidgetChrome.bare)
              _StyleSection(
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

/// The card's name, edited in place at the top of the inspector.
///
/// Deliberately not a labelled form field. It sits where the card's name was
/// already being *shown*, so it reads as the heading it replaces until you
/// click it — which is what makes it discoverable without adding a row of
/// chrome to a panel that already has plenty.
class _TitleField extends StatefulWidget {
  const _TitleField({
    super.key,
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  final String value;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_TitleField> createState() => _TitleFieldState();
}

class _TitleFieldState extends State<_TitleField> {
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
    final style = t.text.subtitleStyle
        .copyWith(color: t.surface.onBase, fontWeight: FontWeight.w600);
    return TextField(
      controller: _controller,
      style: style,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        // An untitled card shows what it is, greyed, rather than an empty box.
        hintText: widget.hint,
        hintStyle: style.copyWith(color: t.surface.onBaseMuted),
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
  const _StyleSection({required this.style, required this.onChanged});

  final CardStyle style;
  final ValueChanged<CardStyle> onChanged;

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
          if (style.isDefault)
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
