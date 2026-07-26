import 'package:flutter/material.dart';

import '../../../design/tokens.dart';
import 'editor_style.dart';

/// The visual shell shared by the device pickers (action + condition): a padded
/// header over three full-bleed panes on their own surface tones, and a footer.
///
/// It owns no navigation state — each picker keeps its own selection/query and
/// hands the shell the built `rail`, `list` and `detail` widgets. The depth
/// (recessed rail/list, raised detail) lives here so both pickers read the same.

/// The live-state tint on a device row's chip.
enum PickerTone { on, play, ok, off }

Color pickerToneColor(HcTokens t, PickerTone? tone) => switch (tone) {
      PickerTone.on => t.accent.active,
      PickerTone.play => t.accent.primary,
      PickerTone.ok => t.accent.success,
      _ => t.surface.onBaseMuted,
    };

/// A rail category: an icon, a label, a count, grouped under a heading.
class PickerCat {
  const PickerCat(this.key, this.label, this.icon, this.group);
  final String key;
  final String label;
  final IconData icon;
  final String group;
}

Widget pickerHline(HcTokens t, {bool vertical = false}) => Container(
      width: vertical ? 1 : null,
      height: vertical ? null : 1,
      color: t.stroke.hairline,
    );

/// One vertical pane inside the shell. A fixed [width] (the rail) or a flexible
/// [flex] share of the rest (the list, the detail form).
class PickerPane {
  const PickerPane({
    required this.child,
    this.width,
    this.flex = 1,
    this.compactLabel,
  });

  final Widget child;
  final double? width;
  final int flex;

  /// What this pane is called when the panel is too narrow to show the panes
  /// side by side and they become steps instead. Null means the pane has no
  /// step of its own — it is folded into the one before it.
  final String? compactLabel;
}

/// The whole panel: `Dialog` → chrome → `Column[header, panes, footer]`.
///
/// The number of panes is up to the caller — the device pickers use three
/// (rail · list · detail), but a picker whose category has no device list is
/// free to use two (rail · form). Only the *style* — the depth, the header and
/// footer — is fixed here.
/// Below this width the panes stop fitting side by side.
///
/// A phone is ~390 logical pixels; a rail at 220 plus a list at 260 plus a
/// detail pane does not go into that, and squeezing them produces three
/// unusable columns rather than one usable one. Above it the panel keeps its
/// panes and merely takes what room there is.
const kPickerCompactWidth = 760.0;

class PickerPanel extends StatefulWidget {
  const PickerPanel({
    super.key,
    required this.kicker,
    required this.title,
    required this.seg,
    required this.panes,
    required this.footerHint,
    required this.primaryLabel,
    required this.onPrimary,
    this.width = 1160,
    this.height = 560,
  });

  final String kicker;
  final String title;
  final Widget seg;
  final List<PickerPane> panes;
  final String footerHint;
  final String primaryLabel;

  /// Null disables the primary button (nothing chosen yet).
  final VoidCallback? onPrimary;

  /// Preferred size. Both are capped by what the viewport actually has — see
  /// the note in [build]. 1160x560 is the three-pane desktop size; a picker
  /// with fewer panes should ask for less rather than stretch to fill.
  final double width;
  final double height;

  @override
  State<PickerPanel> createState() => _PickerPanelState();
}

class _PickerPanelState extends State<PickerPanel> {
  /// Which pane is showing, when the panel is narrow enough to show one.
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.all(t.space.lg),
      // [widget.width] and [widget.height] are a PREFERENCE, not a size. A constant 960x470
      // overflowed anything shorter than about 620 logical pixels — a laptop
      // with browser chrome, a tablet in landscape — and an overflowing dialog
      // clips its own footer, so the primary button becomes unreachable. It
      // was also cut off horizontally on a narrow window.
      //
      // The Dialog's insetPadding gives bounded constraints, so the panel can
      // simply take the smaller of what it wants and what there is.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = widget.width > constraints.maxWidth
              ? constraints.maxWidth
              : widget.width;
          final compact = constraints.maxWidth < kPickerCompactWidth;
          // Panes with a compact label are the steps; the rest fold into the
          // step before them, which is how a rail rides along with its list.
          final steps = <int>[
            for (var i = 0; i < widget.panes.length; i++)
              if (widget.panes[i].compactLabel != null) i,
          ];
          final step = steps.isEmpty ? 0 : _step.clamp(0, steps.length - 1);
          final row = <Widget>[];
          for (var i = 0; i < widget.panes.length; i++) {
            final p = widget.panes[i];
            if (compact && steps.isNotEmpty) {
              // One step at a time: this pane, plus any unlabelled panes that
              // belong to it.
              final owner = steps.lastWhere((x) => x <= i, orElse: () => 0);
              if (owner != steps[step]) continue;
            }
            if (row.isNotEmpty) row.add(pickerHline(t, vertical: true));
            row.add(p.width != null && !compact
                ? SizedBox(width: p.width, child: p.child)
                : Expanded(flex: p.flex, child: p.child));
          }
          return Container(
            width: w,
            decoration: BoxDecoration(
              color: t.surface.overlay,
              borderRadius: BorderRadius.circular(t.radius.lg),
              border:
                  Border.all(color: t.stroke.hairline, width: t.stroke.width),
              boxShadow: t.elevation.overlay,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _header(t, compact),
                if (compact && steps.length > 1) ...[
                  pickerHline(t),
                  _stepBar(t, steps, step),
                ],
                pickerHline(t),
                // Flexible, so the header and footer are laid out first and
                // the widget.panes take what is left — capped at the preferred
                // widget.height so a tall window does not stretch a short list.
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: widget.height),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: row),
                  ),
                ),
                pickerHline(t),
                _footer(context, t, compact, steps, step),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Share the width between the footer's buttons when the panel is narrow.
  Widget _wrap(bool compact, Widget child) =>
      compact ? Expanded(child: child) : child;

  /// The step indicator, shown only when the panel is narrow enough that the
  /// panes have become a sequence.
  Widget _stepBar(HcTokens t, List<int> steps, int step) => Padding(
        padding:
            EdgeInsets.symmetric(horizontal: t.space.lg, vertical: t.space.sm),
        child: Row(children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.chevron_right,
                    size: 14, color: t.surface.onBaseMuted),
              ),
            // Tappable, so a step already passed can be revisited without
            // walking back through the ones after it.
            InkWell(
              onTap: i <= step ? () => setState(() => _step = i) : null,
              child: Text(
                widget.panes[steps[i]].compactLabel!,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: i == step ? FontWeight.w700 : FontWeight.w400,
                  color: i == step ? t.accent.active : t.surface.onBaseMuted,
                ),
              ),
            ),
          ],
        ]),
      );

  Widget _header(HcTokens t, [bool compact = false]) => Padding(
        padding:
            EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.md, t.space.md),
        child: Flex(
            direction: compact ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment:
                compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.kicker,
                            style: TextStyle(
                                fontSize: 10.5,
                                letterSpacing: 1.4,
                                fontWeight: FontWeight.w800,
                                color: t.accent.active)),
                        const SizedBox(height: 3),
                        Text(widget.title,
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: t.surface.onBase)),
                        SizedBox(height: t.space.sm),
                      ],
                    )
                  : Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.kicker,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  letterSpacing: 1.4,
                                  fontWeight: FontWeight.w800,
                                  color: t.accent.active)),
                          const SizedBox(height: 3),
                          Text(widget.title,
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: t.surface.onBase)),
                        ],
                      ),
                    ),
              widget.seg,
            ]),
      );

  Widget _footer(
    BuildContext context,
    HcTokens t,
    bool compact,
    List<int> steps,
    int step,
  ) {
    final onLast = steps.isEmpty || step == steps.length - 1;
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: t.space.lg, vertical: t.space.sm + 2),
      child: Row(children: [
        // The hint is the first thing to go when there is no room: on a phone
        // the buttons matter and a truncated sentence does not.
        if (!compact)
          Expanded(
            child: Text(widget.footerHint,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: t.surface.onBaseMuted)),
          )
        else
          const Spacer(),
        // On a phone the two buttons share the width rather than sitting at
        // their natural size, which overflowed a 390px screen by a few pixels
        // and took the footer's own layout with it.
        _wrap(
          compact,
          compact && step > 0
              ? _FooterBtn(
                  label: 'Back', onTap: () => setState(() => _step = step - 1))
              : _FooterBtn(
                  label: 'Cancel', onTap: () => Navigator.pop(context)),
        ),
        SizedBox(width: t.space.sm),
        // Mid-sequence the primary advances; only the last step commits, so a
        // half-finished choice cannot be submitted by the same button that
        // means "next".
        _wrap(
          compact,
          compact && !onLast
              ? _FooterBtn(
                  label: 'Next',
                  primary: true,
                  onTap: () => setState(() => _step = step + 1),
                )
              : _FooterBtn(
                  label: widget.primaryLabel,
                  primary: true,
                  onTap: widget.onPrimary),
        ),
      ]),
    );
  }
}

class _FooterBtn extends StatelessWidget {
  const _FooterBtn({required this.label, this.onTap, this.primary = false});
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final enabled = onTap != null;
    final bg = primary
        ? (enabled ? t.accent.active : t.surface.raised)
        : Colors.transparent;
    final fg = primary
        ? (enabled ? const Color(0xFF221803) : t.surface.onBaseMuted)
        : t.surface.onBaseMuted;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(t.radius.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(t.radius.pill),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: t.space.lg, vertical: t.space.sm + 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radius.pill),
              border: primary
                  ? null
                  : Border.all(color: t.stroke.hairline, width: t.stroke.width),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: fg)),
          ),
        ),
      ),
    );
  }
}

/// The By-type / By-room segmented control.
Widget pickerSeg(HcTokens t,
        {required bool byRoom, required ValueChanged<bool> onChanged}) =>
    Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _seg(t, 'By type', !byRoom, () => onChanged(false)),
        _seg(t, 'By room', byRoom, () => onChanged(true)),
      ]),
    );

Widget _seg(HcTokens t, String label, bool on, VoidCallback onTap) => Material(
      color: on ? t.surface.raised : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          child: Text(label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: on ? t.surface.onBase : t.surface.onBaseMuted,
              )),
        ),
      ),
    );

/// The category / room rail — a recessed (sunken) column with an info note.
class PickerRail extends StatelessWidget {
  const PickerRail({super.key, required this.children, this.note});

  final List<Widget> children;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      color: t.surface.sunken,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: t.space.xs),
          Expanded(
              child: ListView(padding: EdgeInsets.zero, children: children)),
          if (note != null) ...[
            pickerHline(t),
            Padding(
              padding: EdgeInsets.all(t.space.sm),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline,
                    size: 13, color: t.surface.onBaseMuted),
                SizedBox(width: t.space.xs),
                Expanded(
                  child: Text(note!,
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.4,
                          color: t.surface.onBaseMuted)),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

Widget pickerRailRow(HcTokens t,
    {required String label,
    required IconData icon,
    required int count,
    required bool selected,
    required VoidCallback onTap}) {
  return Material(
    color:
        selected ? t.accent.active.withValues(alpha: 0.12) : Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: selected ? t.accent.active : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(children: [
          Icon(icon,
              size: 17,
              color: selected ? t.surface.onBase : t.surface.onBaseMuted),
          SizedBox(width: t.space.sm),
          Expanded(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? t.surface.onBase : t.surface.onBaseMuted,
                )),
          ),
          Text('$count',
              style: TextStyle(
                  fontSize: 11.5,
                  color: selected ? t.accent.active : t.surface.onBaseMuted)),
        ]),
      ),
    ),
  );
}

/// The device list — a recessed gradient column with a pinned search field.
class PickerDeviceList extends StatelessWidget {
  const PickerDeviceList({
    super.key,
    required this.onQuery,
    required this.rows,
    required this.empty,
  });

  final ValueChanged<String> onQuery;
  final List<Widget> rows;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(t.surface.sunken, t.surface.base, 0.5)!,
            t.surface.sunken,
          ],
        ),
      ),
      child: Column(children: [
        Padding(
          padding: EdgeInsets.all(t.space.sm),
          child: TextField(
            decoration: fieldDecoration(t, hint: 'Search devices…'),
            onChanged: onQuery,
          ),
        ),
        Expanded(
          child: empty
              ? Center(
                  child: Text('No devices match.',
                      style: TextStyle(color: t.surface.onBaseMuted)))
              : ListView(
                  padding: EdgeInsets.symmetric(horizontal: t.space.xs),
                  children: rows),
        ),
      ]),
    );
  }
}

Widget pickerDeviceRow(HcTokens t,
    {required IconData icon,
    required String label,
    required String sub,
    String? chip,
    PickerTone? chipTone,
    required bool selected,
    required VoidCallback onTap}) {
  final tone = pickerToneColor(t, chipTone);
  return Material(
    color:
        selected ? t.accent.active.withValues(alpha: 0.12) : Colors.transparent,
    borderRadius: t.radius.smR,
    child: InkWell(
      onTap: onTap,
      borderRadius: t.radius.smR,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: 8),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.surface.raised,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.stroke.hairline),
            ),
            child: Icon(icon,
                size: 17,
                color: selected ? t.accent.active : t.surface.onBaseMuted),
          ),
          SizedBox(width: t.space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, color: t.surface.onBase)),
                Text(sub,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: t.surface.onBaseMuted)),
              ],
            ),
          ),
          if (chip != null) ...[
            SizedBox(width: t.space.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: tone.withValues(alpha: 0.28)),
              ),
              child: Text(chip,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: tone)),
            ),
          ],
        ]),
      ),
    ),
  );
}

/// A small section label above a group of rows (rooms, RUN, etc.).
Widget pickerGroupLabel(HcTokens t, String text) => Padding(
      padding: EdgeInsets.fromLTRB(t.space.sm, t.space.md, 0, t.space.xs),
      child: RailLabel(text),
    );
