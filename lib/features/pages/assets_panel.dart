import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/assets_api.dart';
import '../../core/models/dashboard.dart';
import '../../core/providers/assets_provider.dart';
import '../../design/tokens.dart';

/// The pictures this house has, as things you can place.
///
/// A tab of its own rather than a section at the bottom of a catalogue. They
/// belong beside the devices for the same reason the devices are here: this
/// panel holds what the *house* has, and a photograph of the kitchen is as much
/// a fact about the house as the lamp in it.
class AssetsPanel extends ConsumerStatefulWidget {
  const AssetsPanel({super.key, required this.onPick});

  final ValueChanged<DashboardWidgetModel> onPick;

  @override
  ConsumerState<AssetsPanel> createState() => _AssetsPanelState();
}

class _AssetsPanelState extends ConsumerState<AssetsPanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final async = ref.watch(assetListProvider);
    final pictures = [
      for (final a in async.value ?? const <AssetRef>[])
        if (a.contentType.startsWith('image/') &&
            (_query.isEmpty || a.name.toLowerCase().contains(_query)))
          a,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: t.space.sm),
          child: TextField(
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search pictures',
              prefixIcon:
                  Icon(Icons.search, size: 16, color: t.surface.onBaseMuted),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        // **Never nothing.** Rendering an empty stretch of panel while the
        // listing was in flight — and, as first written, while it had *failed*
        // — made the whole section appear not to exist, and there is no way to
        // tell "still asking" from "not built yet" by looking at a blank. That
        // is exactly what happened on the live house.
        Expanded(
          child: async.hasError
              ? _Says(
                  text: 'Could not list your files: ${async.error}',
                  colour: t.accent.danger,
                  t: t,
                )
              : async.isLoading
                  ? _Says(text: 'Looking…', colour: t.surface.onBaseMuted, t: t)
                  : pictures.isEmpty
                      ? _Says(
                          text: _query.isEmpty
                              ? 'Nothing uploaded yet. Files you add in '
                                  'Manage → Files land here, ready to place.'
                              : 'No picture by that name.',
                          colour: t.surface.onBaseMuted,
                          t: t,
                        )
                      : SingleChildScrollView(
                          child: Wrap(
                            spacing: t.space.xs,
                            runSpacing: t.space.xs,
                            children: [
                              for (final asset in pictures)
                                _AssetTile(asset: asset, onPick: widget.onPick),
                            ],
                          ),
                        ),
        ),
      ],
    );
  }
}

class _Says extends StatelessWidget {
  const _Says({required this.text, required this.colour, required this.t});
  final String text;
  final Color colour;
  final HcTokens t;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.all(t.space.sm),
        child: Text(text,
            style: t.text.captionStyle.copyWith(color: colour, height: 1.4)),
      );
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.asset, required this.onPick});

  final AssetRef asset;
  final ValueChanged<DashboardWidgetModel> onPick;

  DashboardWidgetModel _card() => DashboardWidgetModel(
        id: 'widget_${DateTime.now().microsecondsSinceEpoch}',
        // Named for the file, so the layer tree says which picture rather than
        // "Image" four times.
        title: asset.name,
        type: 'image',
        refreshPolicy: DashboardRefreshPolicy.passive,
        config: {'url': asset.url, 'fit': 'cover'},
      );

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Tooltip(
      message: asset.name,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: () => onPick(_card()),
        borderRadius: t.radius.smR,
        child: Container(
          width: 104,
          height: 72,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: t.surface.sunken,
            borderRadius: t.radius.smR,
            border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
          ),
          // The picture itself is the label. A filename under a thumbnail
          // would halve the thumbnail to repeat what the tooltip says.
          child: Image.network(
            asset.url,
            fit: BoxFit.cover,
            errorBuilder: (context, _, __) => Center(
              child: Icon(Icons.broken_image_outlined,
                  size: 18, color: t.surface.onBaseMuted),
            ),
          ),
        ),
      ),
    );
  }
}
