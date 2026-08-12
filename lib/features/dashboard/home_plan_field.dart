import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/floor_plan.dart';
import '../../core/dashboard/plan_textures.dart';
import '../../core/dashboard/sweet_home.dart';
import '../../core/providers/assets_provider.dart';
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
/// **The floor textures are the exception, and have to be.** A picture of oak
/// is a file however you look at it, so the ones the floors name are lifted out
/// of the archive and uploaded to the asset store under one group, and each
/// room keeps the address. That is the difference between a drawing of a house
/// and a render of one, and it is the only part of an import that touches the
/// network — so it is also the only part allowed to half-fail: a texture that
/// will not store leaves its room quietly filled, and the plan still lands.
class HomePlanField extends ConsumerStatefulWidget {
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
  ConsumerState<HomePlanField> createState() => _HomePlanFieldState();
}

class _HomePlanFieldState extends ConsumerState<HomePlanField> {
  /// What went wrong, and whether it stopped the import.
  ///
  /// The two are not the same and must not look the same: "that is not a Sweet
  /// Home 3D file" is a refusal, while "one texture would not store" is a home
  /// that imported and drew. In the danger colour, the second reads as the
  /// first and sends someone hunting for a plan that is already on their card.
  ({String text, bool bad})? _note;
  bool _reading = false;

  /// What the field is doing while it is doing it — an import that stores six
  /// textures is six round trips, and a button that has simply gone quiet for
  /// that long reads as a broken one.
  String? _busy;

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
      _busy = 'Reading the home…';
      _note = null;
    });
    try {
      final home = readSweetHome(file.bytes);
      if (home.plan.isEmpty) {
        setState(() => _note =
            (text: 'That home has no walls or rooms in it.', bad: true));
        return;
      }
      final plan = await _store(home);
      if (!mounted) return;
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
    } on PlanImportException catch (e) {
      setState(() => _note = (text: e.message, bad: true));
    } finally {
      if (mounted) {
        setState(() {
          _reading = false;
          _busy = null;
        });
      }
    }
  }

  /// Stores the floors' pictures, and hands back the plan pointing at them.
  ///
  /// The rule itself is [storeTextures] — separate because it is the one step
  /// of an import that can half-fail, and a rule about failure that can only be
  /// exercised against a running house is a rule nobody checks.
  Future<HomePlan> _store(SweetHome home) async {
    final result = await storeTextures(
      home,
      (bytes, {required filename, required contentType, required group}) async {
        final stored = await ref.read(assetsApiProvider).upload(
              bytes,
              filename: filename,
              contentType: contentType,
              group: group,
            );
        return stored.url;
      },
      onProgress: (done, total) {
        if (mounted) {
          setState(() => _busy = 'Storing textures… $done of $total');
        }
      },
    );
    if (result.note case final note? when mounted) {
      setState(() => _note = (text: note, bad: false));
    }
    return result.plan;
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
            // Beside the button rather than replacing its label, so the step
            // that reaches the network is visibly a step and not a stall.
            if (_busy case final busy?) ...[
              SizedBox(width: t.space.sm),
              Flexible(
                child: Text(busy,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted)),
              ),
            ],
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
          Text(
            note.text,
            style: t.text.bodySmallStyle.copyWith(
                color: note.bad ? t.accent.danger : t.surface.onBaseMuted),
          ),
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
                  'file — open the card to say which device each one is. '
                  'Floor textures were stored as files; Dim above holds them '
                  'back behind the house\'s own state.',
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
      // Counted separately from the rooms, because this is the one part of an
      // import that can partly fail and the only place it shows.
      if (plan.rooms.any((r) => r.floor?.isStored == true))
        '${plan.rooms.where((r) => r.floor?.isStored == true).length} '
            'textured',
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
