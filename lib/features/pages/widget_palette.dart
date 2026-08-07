import 'package:flutter/material.dart';

import '../../core/dashboard/widget_registry.dart';
import '../../core/models/dashboard.dart';
import '../../design/tokens.dart';
import '../../shell/hc_sheet.dart';
import 'widget_config_form.dart';

/// The add-a-widget surface.
///
/// It lists whatever the [WidgetRegistry] knows — every built-in AND any card a
/// plugin contributed — so a camera wall and a news iframe are just two more
/// things you pick, not special cases. Returns a ready-to-place widget model, or
/// null if dismissed.
Future<DashboardWidgetModel?> showWidgetPalette(BuildContext context) {
  return showHcSheet<DashboardWidgetModel>(
    context,
    title: 'Add widget',
    child: const _WidgetPalette(),
  );
}

/// Everything a person would add. Config-heavy cards (a history chart, a camera)
/// are in — the config form handles them now — with sensible starting values.
const _addable = <String>[
  'house_status_hero',
  'device_grid',
  'device_list',
  'device_tile',
  'media_player',
  'mode_chips',
  'scene_row',
  'event_feed',
  'history_chart',
  'camera_video',
  'web_embed',
  'markdown',
  'stat_summary',
];

/// Starting values, so a form opens on something reasonable rather than blank.
Map<String, dynamic> _defaultConfig(String type) => switch (type) {
      // Grids/lists open on "query" with an empty query, which means "all
      // devices" — so a freshly added card immediately shows something rather
      // than an empty manual selection you have to discover how to fill.
      'device_grid' || 'device_list' => {
          'selection_mode': 'query',
          'query': '',
          'show_offline': true,
        },
      // A single-device tile / player really does need you to choose one.
      'device_tile' || 'media_player' => {
          'selection_mode': 'manual',
          'device_ids': <String>[],
        },
      'stat_summary' => {
          'metrics': ['devices', 'on', 'offline']
        },
      'markdown' => {'markdown': '# Note\nWrite something here.'},
      'camera_video' => {'source_type': 'image_refresh'},
      'web_embed' => {'sandbox_profile': 'readonly_embed'},
      'event_feed' => {'limit': 20, 'group_by': 'none'},
      'history_chart' => {'timeframe_hours': 24},
      _ => <String, dynamic>{},
    };

class _WidgetPalette extends StatelessWidget {
  const _WidgetPalette();

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final descriptors = [
      for (final type in _addable)
        if (WidgetRegistry.lookup(type) case final d?) d,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HcSheetHeader(
          title: 'Add widget',
          subtitle: 'Camera, a web page, device cards, charts…',
        ),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(t.space.md, 0, t.space.md, t.space.lg),
            itemCount: descriptors.length,
            separatorBuilder: (_, __) => SizedBox(height: t.space.xs),
            itemBuilder: (context, i) {
              final d = descriptors[i];
              return InkWell(
                borderRadius: t.radius.mdR,
                onTap: () => _pick(context, d),
                child: Container(
                  padding: EdgeInsets.all(t.space.md),
                  decoration: BoxDecoration(
                    color: t.surface.raised,
                    borderRadius: t.radius.mdR,
                    border: Border.all(color: t.stroke.hairline),
                  ),
                  child: Row(
                    children: [
                      Icon(d.icon, size: 20, color: t.surface.onBaseMuted),
                      SizedBox(width: t.space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.title,
                                style: t.text.subtitleStyle.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: t.surface.onBase)),
                            if (d.description != null)
                              Text(d.description!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.text.bodySmallStyle
                                      .copyWith(color: t.surface.onBaseMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, WidgetDescriptor d) async {
    var config = _defaultConfig(d.type);

    // A card with options gets the real form; one without (house status, mode
    // chips) drops straight in.
    if (d.configFields.isNotEmpty) {
      final edited =
          await showWidgetConfig(context, descriptor: d, initial: config);
      if (edited == null) return; // cancelled — add nothing
      config = edited;
    }

    if (!context.mounted) return;
    final model = DashboardWidgetModel(
      id: 'widget_${DateTime.now().microsecondsSinceEpoch}',
      type: d.type,
      title: d.title,
      refreshPolicy: DashboardRefreshPolicy.live,
      config: config,
    );
    Navigator.of(context).pop(model);
  }
}
