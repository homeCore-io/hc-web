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
  const PickerPane({required this.child, this.width, this.flex = 1});
  final Widget child;
  final double? width;
  final int flex;
}

/// The whole panel: `Dialog` → chrome → `Column[header, panes, footer]`.
///
/// The number of panes is up to the caller — the device pickers use three
/// (rail · list · detail), but a picker whose category has no device list is
/// free to use two (rail · form). Only the *style* — the depth, the header and
/// footer — is fixed here.
class PickerPanel extends StatelessWidget {
  const PickerPanel({
    super.key,
    required this.kicker,
    required this.title,
    required this.seg,
    required this.panes,
    required this.footerHint,
    required this.primaryLabel,
    required this.onPrimary,
    this.width = 960,
    this.height = 470,
  });

  final String kicker;
  final String title;
  final Widget seg;
  final List<PickerPane> panes;
  final String footerHint;
  final String primaryLabel;

  /// Null disables the primary button (nothing chosen yet).
  final VoidCallback? onPrimary;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final row = <Widget>[];
    for (var i = 0; i < panes.length; i++) {
      if (i > 0) row.add(pickerHline(t, vertical: true));
      final p = panes[i];
      row.add(p.width != null
          ? SizedBox(width: p.width, child: p.child)
          : Expanded(flex: p.flex, child: p.child));
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.all(t.space.lg),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: t.surface.overlay,
          borderRadius: BorderRadius.circular(t.radius.lg),
          border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
          boxShadow: t.elevation.overlay,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(t),
            pickerHline(t),
            SizedBox(
              height: height,
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: row),
            ),
            pickerHline(t),
            _footer(context, t),
          ],
        ),
      ),
    );
  }

  Widget _header(HcTokens t) => Padding(
        padding:
            EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.md, t.space.md),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kicker,
                    style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                        color: t.accent.active)),
                const SizedBox(height: 3),
                Text(title,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: t.surface.onBase)),
              ],
            ),
          ),
          seg,
        ]),
      );

  Widget _footer(BuildContext context, HcTokens t) => Padding(
        padding: EdgeInsets.symmetric(
            horizontal: t.space.lg, vertical: t.space.sm + 2),
        child: Row(children: [
          Text(footerHint,
              style: TextStyle(fontSize: 11.5, color: t.surface.onBaseMuted)),
          const Spacer(),
          _FooterBtn(label: 'Cancel', onTap: () => Navigator.pop(context)),
          SizedBox(width: t.space.sm),
          _FooterBtn(label: primaryLabel, primary: true, onTap: onPrimary),
        ]),
      );
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
