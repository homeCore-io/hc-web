import 'package:flutter/material.dart';

/// A consistent search + chip filter bar used on data-heavy pages.
/// Wrap chips in a horizontally-scrolling row below the search field.
class FilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final String searchHint;
  final List<Widget> chips;        // FilterChip / ChoiceChip widgets
  final Widget? trailing;          // sort dropdown or other control
  final String? countLabel;        // e.g. "Showing 4 of 12"

  const FilterBar({
    super.key,
    required this.searchController,
    required this.searchHint,
    this.chips = const [],
    this.trailing,
    this.countLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: searchHint,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => searchController.clear(),
                          )
                        : null,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 8),
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
        if (chips.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final chip in chips)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: chip,
                  ),
              ],
            ),
          ),
        if (countLabel != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 4),
            child: Row(
              children: [
                Text(countLabel!,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outline,
                    )),
              ],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}
