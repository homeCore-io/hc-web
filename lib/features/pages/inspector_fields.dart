/// The parts an inspector is built from, as opposed to a form.
///
/// **A form asks questions; an inspector shows state.** That difference is not
/// decoration, it is the whole reason the designer read as a web page with a
/// preview attached. A form gives every setting a heading on its own line, a
/// bordered box beneath it the full width of the panel, and a paragraph of help
/// underneath — three lines and 90 pixels for a number between 0 and 360. Ten
/// settings is 900 pixels of scrolling to see the state of one element, so you
/// cannot see the state of one element.
///
/// An inspector puts the name and the value on **one line**, aligns every value
/// down a single column so the panel can be read down rather than read through,
/// and groups the lines under quiet headings. The same ten settings are then
/// 300 pixels and one glance.
///
/// Two consequences worth stating, because they are what make it feel like a
/// tool rather than a page:
///
///   * **Numbers scrub.** Drag the label of a number and the number changes.
///     Every drawing application does this and nobody who has used one goes
///     back to selecting the text and typing — a rotation you can *pull* is a
///     rotation you can find by eye, and typing 37 then 42 then 39 is not.
///   * **Short choices are segments, not menus.** A menu hides four options
///     behind a click and a popup; four segments show which one is on without
///     any interaction at all, which is the point of an inspector.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/components/hc_controls.dart';
import '../../design/tokens.dart';

/// The width of the name column, in logical pixels.
///
/// Fixed rather than intrinsic, and this is what buys the whole layout: every
/// value in the panel starts at the same x, so the eye runs straight down the
/// column of values. Wide enough for the longest label the primitives use
/// ("Stroke width", "Tracking %") at the caption size, and no wider — the
/// controls need the rest.
const double inspectorLabelWidth = 92;

/// One setting: its name, and its value, on one line.
class InspectorField extends StatelessWidget {
  const InspectorField({
    super.key,
    required this.label,
    required this.child,
    this.help,
    this.onScrub,
  });

  final String label;
  final Widget child;

  /// The sentence under the row, for the rare setting that genuinely needs one.
  ///
  /// Deliberately awkward to reach for: help under every field is what turns a
  /// panel into a document. Most settings are explained by their own name and a
  /// value you can see change.
  final String? help;

  /// Dragging the *name* changes the value by this many steps.
  ///
  /// On the label rather than on the field, so the number stays selectable and
  /// typeable — the scrub is an extra way in, never the only one.
  final ValueChanged<int>? onScrub;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs / 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: inspectorLabelWidth,
                child: _Label(label: label, onScrub: onScrub),
              ),
              Expanded(child: child),
            ],
          ),
          if (help case final line?)
            Padding(
              padding: EdgeInsets.only(
                  left: inspectorLabelWidth, top: t.space.xs / 2),
              child: Text(line,
                  style: t.text.captionStyle
                      .copyWith(color: t.surface.onBaseMuted, height: 1.35)),
            ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.label, this.onScrub});

  final String label;
  final ValueChanged<int>? onScrub;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
    );
    if (onScrub == null) return text;
    return MouseRegion(
      // The cursor is the whole discoverability of scrubbing: nothing else on
      // the panel says the label is draggable, and a feature nobody finds is a
      // feature nobody has.
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) {
          // Four pixels a step. Fine enough to land on a value, coarse enough
          // that a whole range is reachable without lifting the mouse.
          final steps = (d.primaryDelta ?? 0) / 4;
          if (steps.abs() < 1) return;
          onScrub!(steps.round());
        },
        child: text,
      ),
    );
  }
}

/// A quiet heading over a run of fields.
///
/// The panel is read down, so the headings have to be legible without being
/// loud — an inspector where the section names compete with the values is one
/// where you read the furniture instead of the state.
class InspectorSection extends StatelessWidget {
  const InspectorSection(
      {super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(top: t.space.md, bottom: t.space.xs),
          child: Text(
            title.toUpperCase(),
            style: t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// A number, shown as a number.
///
/// Borderless on purpose. A box drawn around every value turns a panel of ten
/// settings into a page of ten boxes; the value's own alignment and its
/// tabular figures are enough to say "this is editable" once the whole column
/// does it. The box comes back on focus, which is when it means something.
class InspectorNumber extends StatefulWidget {
  const InspectorNumber({
    super.key,
    required this.value,
    required this.onChanged,
    this.unit,
    this.hint,
    this.min,
    this.max,
  });

  /// Null is a real value: *unset*, which is not the same as zero. A thickness
  /// of nothing means "the skin's hairline" and a thickness of 0 means an
  /// invisible line.
  final num? value;
  final ValueChanged<num?> onChanged;

  /// `px`, `°`, `%` — after the number, in the muted ink, never in the label.
  final String? unit;

  /// What the value is when it is unset, so the field can say so rather than
  /// sitting empty and looking broken.
  final String? hint;

  final num? min;
  final num? max;

  @override
  State<InspectorNumber> createState() => _InspectorNumberState();
}

class _InspectorNumberState extends State<InspectorNumber> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value?.toString() ?? '');
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(InspectorNumber old) {
    super.didUpdateWidget(old);
    // Follow the model when the change came from somewhere else — a scrub, an
    // undo, a different element selected. Not while the field has focus, or a
    // reformat would fight the person typing into it.
    if (_focus.hasFocus) return;
    final text = widget.value?.toString() ?? '';
    if (text != _controller.text) _controller.text = text;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      height: t.density.controlHeight,
      padding: EdgeInsets.symmetric(horizontal: t.space.xs),
      decoration: BoxDecoration(
        color: _focus.hasFocus ? t.surface.sunken : null,
        borderRadius: BorderRadius.circular(t.radius.xs),
        border: Border.all(
          color: _focus.hasFocus ? t.accent.active : Colors.transparent,
          width: t.stroke.width,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
              ],
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: t.text.bodySmallStyle.copyWith(
                    color: t.surface.onBaseMuted.withValues(alpha: .6)),
              ),
              style: t.text.bodySmallStyle.copyWith(
                color: t.surface.onBase,
                // Figures that do not shuffle width as they change, which is
                // what makes a column of numbers readable while one is being
                // scrubbed.
                fontFeatures: t.numericFontFeatures,
              ),
              onChanged: (raw) {
                if (raw.trim().isEmpty) return widget.onChanged(null);
                final parsed = num.tryParse(raw);
                if (parsed != null) widget.onChanged(_clamped(parsed));
              },
            ),
          ),
          if (widget.unit case final unit?)
            Text(unit,
                style:
                    t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
        ],
      ),
    );
  }

  num _clamped(num value) {
    var out = value;
    if (widget.min case final low?) out = out < low ? low : out;
    if (widget.max case final high?) out = out > high ? high : out;
    return out;
  }
}

/// A small set of choices, all visible at once.
///
/// The rule for reaching for this rather than a menu is in
/// [InspectorChoice.segmented]: it is about how much room the options need,
/// not about how important they are.
class InspectorSegments extends StatelessWidget {
  const InspectorSegments({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labelFor,
  });

  final List<String> options;
  final String? value;
  final ValueChanged<String> onChanged;
  final String Function(String)? labelFor;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      height: t.density.controlHeight,
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: BorderRadius.circular(t.radius.xs),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: _Segment(
                label: labelFor?.call(option) ?? option,
                on: option == value,
                onTap: () => onChanged(option),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? t.surface.raised : null,
          borderRadius: BorderRadius.circular(t.radius.xs),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.text.captionStyle.copyWith(
            color: on ? t.surface.onBase : t.surface.onBaseMuted,
            fontWeight: on ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// The longer list, behind a click.
class InspectorMenu extends StatelessWidget {
  const InspectorMenu({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labelFor,
    this.hint,
  });

  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String Function(String)? labelFor;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      height: t.density.controlHeight,
      padding: EdgeInsets.symmetric(horizontal: t.space.xs),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: BorderRadius.circular(t.radius.xs),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.contains(value) ? value : null,
          isExpanded: true,
          isDense: true,
          hint: hint == null
              ? null
              : Text(hint!,
                  style: t.text.bodySmallStyle
                      .copyWith(color: t.surface.onBaseMuted)),
          icon: Icon(Icons.expand_more, size: 16, color: t.surface.onBaseMuted),
          style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
          dropdownColor: t.surface.overlay,
          borderRadius: BorderRadius.circular(t.radius.sm),
          items: [
            for (final option in options)
              DropdownMenuItem(
                value: option,
                child: Text(labelFor?.call(option) ?? option,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// On or off, on the right of its own name.
class InspectorSwitch extends StatelessWidget {
  const InspectorSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: HcToggle(
          value: value,
          onChanged: onChanged,
          semanticLabel: semanticLabel,
        ),
      );
}

/// Whether a set of options is small enough to show all at once.
abstract final class InspectorChoice {
  /// Segments when there are few options and their names are short.
  ///
  /// Both conditions matter and for the same reason — the row is about 200
  /// pixels wide. Five options, or one called "Everything in this area", would
  /// each ellipsise into a row of `Ev…` that says less than a closed menu does.
  static bool segmented(List<String> options, String Function(String) label) {
    if (options.length > 4 || options.isEmpty) return false;
    final longest =
        options.map((o) => label(o).length).reduce((a, b) => a > b ? a : b);
    return longest <= 9;
  }
}
