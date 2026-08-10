import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/assets_api.dart';
import '../../core/assets/asset_usage.dart';
import '../../core/providers/assets_provider.dart';
import '../../core/providers/dashboards_provider.dart';
import '../../core/providers/skins_provider.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/components/hc_rows.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';

/// The files the house is holding.
///
/// Uploading was the easy half. Nothing auto-deletes and nothing
/// reference-counts — core keeps a blob until it is told not to — so without
/// this page the only way to find out what is on the disk is to look at the
/// disk, and the only way to remove anything is never.
///
/// Two things make deletion safe enough to offer: **what would break is shown
/// before you delete it**, computed by searching the dashboards and skins the
/// client already has; and a deleted asset is a missing picture rather than a
/// broken page, exactly as a stale URL has always been.
class AssetsPage extends ConsumerStatefulWidget {
  const AssetsPage({super.key});

  @override
  ConsumerState<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends ConsumerState<AssetsPage> {
  bool _working = false;
  String? _status;

  bool get _failed => _status?.contains('failed') ?? false;

  Future<void> _run(String verb, Future<void> Function() body) async {
    setState(() {
      _working = true;
      _status = null;
    });
    try {
      await body();
      ref.invalidate(assetListProvider);
      if (!mounted) return;
      setState(() {
        _working = false;
        _status = '$verb done';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _status = '$verb failed: $e';
      });
    }
  }

  Future<void> _delete(AssetRef asset, AssetUsage usage) async {
    final ok = await _confirm(
      title: 'Delete ${asset.name}?',
      // The stakes, stated as what will actually happen rather than as a
      // warning: a page that pointed at this draws its empty state.
      description: usage.isEmpty
          ? 'Nothing points at it. ${formatBytes(asset.size)} comes back.'
          : '${usage.summary} still points at it. They will show an empty '
              'picture until something else is chosen.',
      danger: true,
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    await _run('Delete', () => ref.read(assetsApiProvider).delete(asset.id));
  }

  Future<void> _deleteGroup(String group, int count) async {
    final ok = await _confirm(
      title: 'Delete all $count in "$group"?',
      description: 'Everything uploaded together as "$group" goes at once. '
          'Anything still pointing at one of them shows an empty picture.',
      danger: true,
      confirmLabel: 'Delete $count',
    );
    if (!ok) return;
    await _run('Delete', () => ref.read(assetsApiProvider).deleteGroup(group));
  }

  Future<bool> _confirm({
    required String title,
    required String description,
    required String confirmLabel,
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => HcDialog(
        title: title,
        description: description,
        width: 460,
        actions: [
          HcButton(
            label: 'Cancel',
            kind: HcButtonKind.ghost,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          HcButton(
            label: confirmLabel,
            kind: danger ? HcButtonKind.danger : HcButtonKind.primary,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        // The stakes are the description; there is no form to show.
        child: const SizedBox.shrink(),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final assets = ref.watch(assetListProvider);
    final dashboards = ref.watch(dashboardsProvider).value ?? const [];
    final skins = ref.watch(skinsProvider).value ?? const [];

    return SectionScaffold(
      title: 'Files',
      subtitle: 'Pictures and fonts stored by the house',
      child: ListView(
        padding: EdgeInsets.all(t.space.lg),
        children: [
          if (_status != null) ...[
            HcRowsNotice(
              title: _status!,
              icon: _failed ? Icons.error_outline : Icons.check_circle_outline,
              danger: _failed,
            ),
            SizedBox(height: t.space.md),
          ],
          assets.when(
            loading: () => const HcRowsLoading(rows: 3),
            error: (e, _) =>
                HcRowsNotice.error(title: 'Files unavailable', detail: '$e'),
            data: (list) {
              if (list.isEmpty) {
                return const HcRowsNotice(
                  icon: Icons.folder_outlined,
                  title: 'Nothing stored',
                  detail: 'Pictures and fonts arrive here when you choose a '
                      'file instead of pasting an address — on a card, a page '
                      'background, or a skin.',
                );
              }
              final usage = assetUsage(
                assets: list,
                dashboards: dashboards,
                skins: skins,
              );
              final groups = <String, int>{};
              for (final a in list) {
                if (a.group != null) {
                  groups[a.group!] = (groups[a.group!] ?? 0) + 1;
                }
              }
              final total = list.fold<int>(0, (n, a) => n + a.size);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionLabel(
                      '${list.length} file${list.length == 1 ? '' : 's'} · '
                      '${formatBytes(total)}'),
                  HcRows([
                    for (final asset in list)
                      HcRow(
                        icon: asset.contentType.startsWith('image/')
                            ? Icons.image_outlined
                            : Icons.text_fields,
                        label: asset.name,
                        subtitle: _subtitleFor(asset, usage[asset.id]),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Thumb(asset: asset),
                            SizedBox(width: t.space.sm),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              tooltip: 'Delete',
                              onPressed: _working
                                  ? null
                                  : () => _delete(
                                      asset,
                                      usage[asset.id] ??
                                          const AssetUsage([], [])),
                            ),
                          ],
                        ),
                      ),
                  ]),
                  if (groups.isNotEmpty) ...[
                    SizedBox(height: t.space.lg),
                    // Groups exist for the case that motivated the whole
                    // store: one floor plan import is dozens of textures, and
                    // removing the plan should not mean hunting them by hand.
                    const SectionLabel('Uploaded together'),
                    HcRows([
                      for (final g in groups.entries)
                        HcRow(
                          icon: Icons.folder_copy_outlined,
                          label: g.key,
                          subtitle: '${g.value} file${g.value == 1 ? '' : 's'}',
                          trailing: HcButton(
                            label: 'Delete all',
                            kind: HcButtonKind.danger,
                            onPressed: _working
                                ? null
                                : () => _deleteGroup(g.key, g.value),
                          ),
                        ),
                    ]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _subtitleFor(AssetRef asset, AssetUsage? usage) {
    return [
      asset.contentType,
      formatBytes(asset.size),
      // Which set it arrived in, on the row itself. Without this the "Delete
      // all" below is a button with no visible relationship to anything above
      // it, and the two files it would take are indistinguishable from the two
      // it would not.
      if (asset.group != null) 'in ${asset.group}',
      // "Nothing points at it" rather than silence: the asset with no mention
      // is the one that is safe to remove, and that is worth saying out loud
      // on a page whose whole job is deciding what to remove.
      usage?.summary ?? 'nothing points at it',
    ].join(' · ');
  }
}

/// What it looks like, or what kind it is when it has no look.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.asset});
  final AssetRef asset;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final isImage = asset.contentType.startsWith('image/');
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: t.radius.smR,
        border: Border.all(color: t.stroke.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: isImage
          ? Image.network(
              asset.url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined,
                  size: 15, color: t.surface.onBaseMuted),
            )
          : Icon(Icons.text_fields, size: 15, color: t.surface.onBaseMuted),
    );
  }
}
