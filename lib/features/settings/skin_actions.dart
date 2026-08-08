import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/skin_document.dart';
import '../../core/providers/skin_provider.dart';
import '../../core/providers/skins_provider.dart';
import '../../design/builtin_seeds.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/skin_resolve.dart';
import '../../design/skins.dart';
import '../../design/tokens.dart';

/// Duplicate, rename and delete for the skin gallery.
///
/// Step 5 of `theme-editor-plan.md`. Kept out of the page for the same reason
/// `page_actions.dart` is: these are the operations, the page is the
/// arrangement, and a dialog buried in a build method is one nobody finds.
///
/// **Built-ins are duplicated, never edited.** That is the whole shape of the
/// gallery: you cannot change Midnight, but you can make Hallway out of it in
/// one click. It solves the blank-page problem without a mode — a new skin
/// always starts as something that already works, rather than as a form full of
/// empty colour fields.

/// Forks a built-in into a new user skin and selects it.
Future<void> duplicateBuiltIn(
    BuildContext context, WidgetRef ref, HcSkin skin) async {
  final seeds = builtInSeeds[skin];
  if (seeds == null) return;
  await _create(
    context,
    ref,
    SkinDocument(
      id: _newId(),
      name: '${skin.label} copy',
      base: _coreName(skin),
      seeds: seedsToJson(seeds),
      // A built-in that names its own sensor hues carries them as overrides —
      // the seed format has no `metric`, and a fork that lost them would not be
      // a copy. See `metricOverrides`.
      overrides: metricOverrides(seeds),
    ),
  );
}

/// Forks an existing user skin, overrides and all.
Future<void> duplicateSkin(
    BuildContext context, WidgetRef ref, SkinDocument doc) async {
  await _create(
    context,
    ref,
    SkinDocument(
      id: _newId(),
      name: '${doc.name} copy',
      base: doc.base,
      seeds: Map<String, dynamic>.from(doc.seeds),
      overrides: Map<String, String>.from(doc.overrides),
    ),
  );
}

Future<void> renameSkin(
    BuildContext context, WidgetRef ref, SkinDocument doc) async {
  final name =
      await promptForName(context, title: 'Rename skin', initial: doc.name);
  if (name == null || name.isEmpty) return;
  try {
    await ref.read(skinsApiProvider).updateSkin(SkinDocument(
          id: doc.id,
          name: name,
          base: doc.base,
          seeds: doc.seeds,
          overrides: doc.overrides,
        ));
    await ref.read(skinsProvider.notifier).reload();
  } catch (e) {
    if (context.mounted) _say(context, 'Could not rename: $e');
  }
}

/// Deletes a skin, asking first.
///
/// Deleting the one currently worn is allowed — the resolver falls back to the
/// shell's default, so the app stays dressed. The alternative would be a skin
/// you can only remove by first going somewhere else to stop wearing it.
Future<void> deleteSkin(
    BuildContext context, WidgetRef ref, SkinDocument doc) async {
  final worn = ref.read(skinOverrideProvider).dataId == doc.id;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => HcDialog(
      title: 'Delete this skin?',
      description: worn
          ? '"${doc.name}" is the skin you are wearing. The app falls back to '
              'its default.'
          : '"${doc.name}" is removed for good.',
      actions: [
        HcButton(
            label: 'Cancel', onPressed: () => Navigator.pop(context, false)),
        HcButton(
          label: 'Delete',
          kind: HcButtonKind.danger,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
      child: const SizedBox.shrink(),
    ),
  );
  if (confirmed != true) return;

  try {
    await ref.read(skinsApiProvider).deleteSkin(doc.id);
    if (worn) {
      // Stop pointing at something that is gone. The resolver would cope, but
      // leaving a dead id in preferences means the next skin created with a
      // recycled id would be silently worn.
      await ref
          .read(skinOverrideProvider.notifier)
          .choose(const SkinChoice.none());
    }
    await ref.read(skinsProvider.notifier).reload();
  } catch (e) {
    if (context.mounted) _say(context, 'Could not delete: $e');
  }
}

Future<void> _create(
    BuildContext context, WidgetRef ref, SkinDocument doc) async {
  final name =
      await promptForName(context, title: 'New skin', initial: doc.name);
  if (name == null || name.isEmpty) return;
  try {
    final created = await ref.read(skinsApiProvider).createSkin(SkinDocument(
          id: doc.id,
          name: name,
          base: doc.base,
          seeds: doc.seeds,
          overrides: doc.overrides,
        ));
    await ref.read(skinsProvider.notifier).reload();
    // Wear it immediately. A fork you cannot see is a fork you cannot judge,
    // and judging it is the entire reason for making one.
    await ref
        .read(skinOverrideProvider.notifier)
        .choose(SkinChoice.data(created.id));
  } catch (e) {
    if (context.mounted) _say(context, 'Could not create: $e');
  }
}

/// Ids are generated, never typed. A skin's name is the thing a person picks;
/// its id is only ever a key, and letting someone choose one invites a
/// collision with a built-in's name — which the resolver would shadow, leaving
/// a skin that saves and can never be worn.
String _newId() => 'skin_${DateTime.now().microsecondsSinceEpoch}';

String _coreName(HcSkin skin) => switch (skin) {
      HcSkin.midnight => 'midnight',
      HcSkin.ambientGlass => 'ambient_glass',
      HcSkin.controlRoom => 'control_room',
      HcSkin.softHome => 'soft_home',
    };

void _say(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<String?> promptForName(BuildContext context,
    {required String title, required String initial}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) {
      final t = HcTokens.of(context);
      return HcDialog(
        title: title,
        actions: [
          HcButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
          HcButton(
            label: 'Save',
            kind: HcButtonKind.primary,
            onPressed: () => Navigator.pop(context, controller.text.trim()),
          ),
        ],
        child: Container(
          decoration: BoxDecoration(
            color: t.surface.sunken,
            borderRadius: BorderRadius.circular(t.radius.sm),
            border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
          ),
          padding: EdgeInsets.symmetric(
              horizontal: t.space.sm, vertical: t.space.xs),
          child: TextField(
            controller: controller,
            autofocus: true,
            style: t.text.bodyStyle.copyWith(color: t.surface.onBase),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
            decoration:
                const InputDecoration(isDense: true, border: InputBorder.none),
          ),
        ),
      );
    },
  );
}
