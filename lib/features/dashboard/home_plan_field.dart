import 'package:flutter/material.dart';

import '../../core/dashboard/floor_plan.dart';
import '../../core/dashboard/sweet_home.dart';
import '../../core/web/browser_files.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';

/// The way a Sweet Home 3D file becomes a plan.
///
/// The import happens **here, in the browser**, and what it leaves behind is
/// geometry in the dashboard document — not a file. That is what lets the app
/// draw the home itself: sharp at any zoom, in the skin's own palette, and
/// invertible by construction rather than by filter.
///
/// It reads the whole archive and keeps the numbers. The JPEG textures inside
/// are files and belong in the asset store, so a plan imported here is a good
/// drawing rather than a render — which is the half that works today.
class HomePlanField extends StatefulWidget {
  const HomePlanField({
    super.key,
    required this.config,
    required this.onChanged,
  });

  /// The whole card config: this field owns two keys — the geometry and which
  /// storey the card is showing — and they only make sense together.
  final Map<String, dynamic> config;

  /// The keys to change, with null to remove one.
  final ValueChanged<Map<String, Object?>> onChanged;

  @override
  State<HomePlanField> createState() => _HomePlanFieldState();
}

class _HomePlanFieldState extends State<HomePlanField> {
  String? _note;
  bool _reading = false;

  /// The whole imported home, every storey — not [planFromConfig], which
  /// narrows to the one being drawn and would hide the others from the picker.
  HomePlan? get _plan {
    final raw = widget.config['plan'];
    if (raw is! Map) return null;
    final plan = HomePlan.fromJson(raw.cast<String, dynamic>());
    return plan.isEmpty ? null : plan;
  }

  Future<void> _import() async {
    final file = await pickFile(accept: '.sh3d');
    if (file == null || !mounted) return;
    setState(() {
      _reading = true;
      _note = null;
    });
    try {
      final plan = readSweetHome(file.bytes);
      if (plan.isEmpty) {
        setState(() => _note = 'That home has no walls or rooms in it.');
        return;
      }
      // Every lamp in the file, already at its own coordinates — or nothing at
      // all, if this card already has markers on it. See [seedMarkersFor].
      final seed = seedMarkersFor(widget.config, plan);

      widget.onChanged({
        'plan': plan.toJson(),
        // A home with one storey has nothing to choose, and one with several
        // starts at the bottom — which is the floor someone means by "the
        // plan" nine times out of ten.
        'level': plan.levels.length > 1 ? plan.levels.first.id : null,
        if (seed != null && seed.isNotEmpty)
          'markers': [for (final m in seed) m.toJson()],
      });
      setState(() => _note = null);
    } on PlanImportException catch (e) {
      setState(() => _note = e.message);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final plan = _plan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plan != null) ...[
          Text(_describe(plan),
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted)),
          if (plan.levels.length > 1) ...[
            SizedBox(height: t.space.sm),
            _Storeys(
              levels: plan.levels,
              value: widget.config['level'] as String?,
              onChanged: (id) => widget.onChanged({'level': id}),
            ),
          ],
          SizedBox(height: t.space.sm),
        ],
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _reading ? null : _import,
              icon: const Icon(HcIcons.plus, size: 14),
              label: Text(plan == null ? 'Import a home' : 'Replace'),
            ),
            if (plan != null) ...[
              SizedBox(width: t.space.sm),
              TextButton(
                onPressed: () =>
                    widget.onChanged({'plan': null, 'level': null}),
                child: Text('Remove',
                    style:
                        t.text.bodySmallStyle.copyWith(color: t.accent.danger)),
              ),
            ],
          ],
        ),
        if (_note case final note?) ...[
          SizedBox(height: t.space.xs),
          Text(note,
              style: t.text.bodySmallStyle.copyWith(color: t.accent.danger)),
        ],
        SizedBox(height: t.space.xs),
        Text(
          plan == null
              // The one thing here that surprises people, said before they hit
              // it: a perspective render is a picture and can never gain rooms,
              // because only a top-down view registers with the geometry.
              ? 'A .sh3d from Sweet Home 3D. The walls, rooms and furniture are '
                  'drawn by the app in your skin. Pair it with a top-down '
                  'render in Picture above to get both — a perspective render '
                  'will not line up.'
              : 'Drawn in your skin, so it follows the theme and stays sharp '
                  'at any size. A marker was placed for each light in the '
                  'file — open the card to say which device each one is.',
          style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
        ),
      ],
    );
  }

  /// What came in, counted — the only honest confirmation that an import
  /// worked, since the card may be scrolled out of sight while you look at it.
  String _describe(HomePlan plan) {
    final parts = <String>[
      if (plan.rooms.isNotEmpty) _count(plan.rooms.length, 'room'),
      if (plan.walls.isNotEmpty) _count(plan.walls.length, 'wall'),
      if (plan.lights.isNotEmpty) _count(plan.lights.length, 'light'),
    ];
    if (parts.isEmpty) return 'A home with nothing in it.';
    return parts.join(', ');
  }

  String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
}

/// Which storey this card is.
///
/// Two storeys are two cards — the grid already knows how to put two things on
/// a page, and a plan that navigated between floors would be a second, worse
/// grid inside a card.
class _Storeys extends StatelessWidget {
  const _Storeys({
    required this.levels,
    required this.value,
    required this.onChanged,
  });

  final List<PlanLevel> levels;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return DropdownButtonFormField<String?>(
      initialValue: levels.any((l) => l.id == value) ? value : null,
      isDense: true,
      decoration: const InputDecoration(
          isDense: true, border: OutlineInputBorder(), labelText: 'Storey'),
      style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
      items: [
        const DropdownMenuItem(value: null, child: Text('All')),
        for (final (index, level) in levels.indexed)
          DropdownMenuItem(
            value: level.id,
            child: Text(level.name?.trim().isNotEmpty == true
                ? level.name!
                : 'Storey ${index + 1}'),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
