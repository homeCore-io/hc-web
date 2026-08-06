import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// The pill search field every list section shares — from the Devices toolbar.
class SectionSearchField extends StatelessWidget {
  const SectionSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      height: 40,
      padding: EdgeInsets.symmetric(horizontal: t.space.md),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: BorderRadius.circular(t.radius.pill),
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 15, color: t.surface.onBaseMuted),
          SizedBox(width: t.space.sm),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: t.text.bodyStyle.copyWith(color: t.surface.onBase),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle:
                    t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A selectable filter pill — the shared chip for every section's filter row.
class SectionChip extends StatelessWidget {
  const SectionChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? t.accent.active.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(t.radius.pill),
          border: Border.all(
              color: selected ? Colors.transparent : t.stroke.hairline),
        ),
        child: Text(label,
            style: t.text.bodySmallStyle.copyWith(
                fontWeight: FontWeight.w600,
                color: selected ? t.accent.active : t.surface.onBaseMuted)),
      ),
    );
  }
}

/// A pill "menu" trigger (Group ▾ / Sort ▾) styled to match the chips.
class SectionMenuButton extends StatelessWidget {
  const SectionMenuButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.keyboard_arrow_down_rounded,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.radius.pill),
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: t.text.bodySmallStyle
                    .copyWith(color: t.surface.onBaseMuted)),
            const SizedBox(width: 3),
            Icon(icon, size: 15, color: t.surface.onBaseMuted),
          ],
        ),
      ),
    );
  }
}

/// The shared toolbar layout: a pill search with trailing controls, then a row
/// of filter chips beneath. Sections supply their own [trailing] menus and
/// [chips]; the search + spacing are identical everywhere.
class SectionToolbar extends StatelessWidget {
  const SectionToolbar({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.trailing = const [],
    this.chips = const [],
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final List<Widget> trailing;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SectionSearchField(
                  controller: controller, hint: hint, onChanged: onChanged),
            ),
            for (final w in trailing) ...[SizedBox(width: t.space.sm), w],
          ],
        ),
        if (chips.isNotEmpty) ...[
          SizedBox(height: t.space.sm),
          Wrap(spacing: 6, runSpacing: 6, children: chips),
        ],
      ],
    );
  }
}
