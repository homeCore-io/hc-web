import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/dashboard.dart';
import '../../core/providers/dashboards_provider.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/components/hc_surface.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../pages/page_actions.dart';
import 'dashboard_drift_notice.dart';

/// Every page in the house, and the three things only this surface can do:
/// reload from disk, import, and start from a template.
///
/// It was the last dashboard surface built out of Material — `AppBar`, `Card`,
/// `Chip`, `Theme.of(...).textTheme`, fifteen Material icons and eight literal
/// spacings. That looked fine, because `hcTheme` feeds the skin's colours and
/// type ramp into `ThemeData` and Material picks them up. What it could not
/// pick up is everything a skin says that Material has no slot for: the corner
/// scale (Control Room's 2/3/5 against Soft Home's 6/12/20), the spacing unit
/// (6 against 8), density and tap targets, and the icon set. So the page was
/// half-skinned in a way that read as fine until you switched to a skin with a
/// strong opinion and this one page ignored it.
///
/// Every value here now comes from [HcTokens].
class DashboardsPage extends ConsumerWidget {
  const DashboardsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final dashboardsAsync = ref.watch(dashboardsProvider);

    return Scaffold(
      backgroundColor: t.surface.base,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => createPage(context, ref),
        backgroundColor: t.accent.active,
        foregroundColor: t.accent.onPrimary,
        icon: const Icon(HcIcons.plus, size: 16),
        label: Text('New page', style: t.text.bodyStyle),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(ref: ref),
            // Silent unless this app and the core in front of it actually
            // disagree about what a dashboard may contain. See
            // DashboardDriftNotice.
            const DashboardDriftNotice(),
            Expanded(
              child: dashboardsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _Notice(text: 'Could not load pages: $e'),
                data: (dashboards) => dashboards.isEmpty
                    ? const _Notice(
                        text: 'No pages yet. Create one to get started.')
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                            t.space.lg, 0, t.space.lg, t.space.xl),
                        itemBuilder: (context, index) =>
                            _DashboardCard(dashboard: dashboards[index]),
                        separatorBuilder: (_, __) =>
                            SizedBox(height: t.space.sm),
                        itemCount: dashboards.length,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding:
          EdgeInsets.fromLTRB(t.space.lg, t.space.lg, t.space.lg, t.space.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Pages',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.text.displayStyle.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                color: t.surface.onBase,
              ),
            ),
          ),
          // Labelled rather than icon-only: the icon vocabulary is Phosphor and
          // deliberately small — it has no reload, import or template glyph, and
          // inventing a codepoint is how you ship a blank box. Three words are
          // clearer than three ambiguous symbols anyway.
          Wrap(
            spacing: t.space.xs,
            children: [
              HcButton(
                label: 'Reload',
                onPressed: () => _reload(context, ref),
              ),
              HcButton(
                label: 'Import',
                onPressed: () => _showImportDialog(context, ref),
              ),
              HcButton(
                label: 'From template',
                onPressed: () => _showTemplateDialog(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Pages are files on disk as well as records in core, so one edited or
  /// restored by hand is invisible until core re-reads them.
  Future<void> _reload(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(dashboardsApiProvider).reload();
      ref.invalidate(dashboardsProvider);
      messenger
          .showSnackBar(const SnackBar(content: Text('Reloaded from disk.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Reload failed: $e')));
    }
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(t.space.lg),
        child: Text(text,
            textAlign: TextAlign.center,
            style: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted)),
      ),
    );
  }
}

class _DashboardCard extends ConsumerWidget {
  const _DashboardCard({required this.dashboard});

  final DashboardDefinition dashboard;

  /// A page's icon, resolved inside the app's vocabulary.
  ///
  /// The old map reached for Material glyphs that have no Phosphor counterpart
  /// here (`chair`, `tablet_mac`). Those fall back to the pages mark rather than
  /// pulling a second icon family onto the screen for two rare cases.
  IconData get _icon => switch (dashboard.icon) {
        'rocket' || 'getting-started' => HcIcons.rocket,
        'shield' => HcIcons.security,
        'play' => HcIcons.play,
        'home' => HcIcons.home,
        _ => HcIcons.dashboards,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);

    return HcSurface(
      padding: EdgeInsets.all(t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon, size: 18, color: t.surface.onBaseMuted),
              SizedBox(width: t.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dashboard.name,
                      style: t.text.subtitleStyle
                          .copyWith(color: t.surface.onBase),
                    ),
                    if (dashboard.description?.isNotEmpty ?? false)
                      Padding(
                        padding: EdgeInsets.only(top: t.space.xs / 2),
                        child: Text(
                          dashboard.description!,
                          style: t.text.bodySmallStyle
                              .copyWith(color: t.surface.onBaseMuted),
                        ),
                      ),
                  ],
                ),
              ),
              if (dashboard.isDefault) const _Tag(label: 'Default', lit: true),
            ],
          ),
          if (dashboard.tags.isNotEmpty) ...[
            SizedBox(height: t.space.sm),
            Wrap(
              spacing: t.space.xs,
              runSpacing: t.space.xs,
              children: [
                for (final tag in dashboard.tags) _Tag(label: tag),
              ],
            ),
          ],
          SizedBox(height: t.space.sm),
          Wrap(
            spacing: t.space.xs,
            runSpacing: t.space.xs,
            children: [
              HcButton(
                label: 'Open',
                kind: HcButtonKind.primary,
                onPressed: () => context.go('/pages/${dashboard.id}'),
              ),
              HcButton(
                label: 'Duplicate',
                icon: HcIcons.copy,
                onPressed: () => ref
                    .read(dashboardsProvider.notifier)
                    .duplicateDashboard(dashboard.id),
              ),
              if (!dashboard.isDefault)
                HcButton(
                  label: 'Set as Home',
                  onPressed: () => ref
                      .read(dashboardsProvider.notifier)
                      .setDefault(dashboard.id),
                ),
              HcButton(
                label: 'Export',
                onPressed: () => _showExportDialog(context, ref, dashboard),
              ),
              HcButton(
                label: 'Delete',
                kind: HcButtonKind.danger,
                icon: HcIcons.trash,
                onPressed: () => _confirmDelete(context, ref, dashboard),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small label — the page's default marker, and its tags.
///
/// `lit` is the one that means something: it marks the page the house opens on.
class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.lit = false});

  final String label;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final fg = lit ? t.accent.active : t.surface.onBaseMuted;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: t.space.sm, vertical: t.space.xs / 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.radius.pill),
        border: Border.all(color: fg, width: t.stroke.width),
      ),
      child: Text(label, style: t.text.captionStyle.copyWith(color: fg)),
    );
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  DashboardDefinition dashboard,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => HcDialog(
      title: 'Delete this page?',
      description: '"${dashboard.name}" and its layouts are removed for good.',
      actions: [
        HcButton(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context, false),
        ),
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
  await ref.read(dashboardsProvider.notifier).deleteDashboard(dashboard.id);
}

Future<void> _showTemplateDialog(BuildContext context, WidgetRef ref) async {
  final templates = await ref.read(dashboardTemplatesProvider.future);
  if (!context.mounted) return;
  final templateId = await showDialog<String>(
    context: context,
    builder: (context) {
      final t = HcTokens.of(context);
      return HcDialog(
        title: 'Start from a template',
        actions: [
          HcButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(context),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final template in templates)
              Padding(
                padding: EdgeInsets.only(bottom: t.space.xs),
                child: HcSurface(
                  padding: EdgeInsets.all(t.space.sm),
                  onTap: () => Navigator.pop(context, template.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(template.name,
                          style: t.text.bodyStyle
                              .copyWith(color: t.surface.onBase)),
                      Text(template.description ?? template.id,
                          style: t.text.captionStyle
                              .copyWith(color: t.surface.onBaseMuted)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
  if (templateId == null) return;
  await ref.read(dashboardsProvider.notifier).createFromTemplate(templateId);
}

Future<void> _showExportDialog(
  BuildContext context,
  WidgetRef ref,
  DashboardDefinition dashboard,
) async {
  final exported =
      await ref.read(dashboardsProvider.notifier).exportDashboard(dashboard.id);
  if (!context.mounted) return;
  final controller = TextEditingController(
    text: const JsonEncoder.withIndent('  ').convert(exported.toJson()),
  );
  await showDialog<void>(
    context: context,
    builder: (context) => HcDialog(
      title: 'Export ${dashboard.name}',
      description: 'Copy this and paste it into Import on another house.',
      width: 700,
      actions: [
        HcButton(label: 'Close', onPressed: () => Navigator.pop(context)),
      ],
      child: _JsonField(controller: controller, label: 'Page JSON'),
    ),
  );
}

Future<void> _showImportDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final error = ValueNotifier<String?>(null);

  final imported = await showDialog<DashboardDefinition>(
    context: context,
    builder: (context) => HcDialog(
      title: 'Import a page',
      width: 700,
      actions: [
        HcButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        HcButton(
          label: 'Import',
          kind: HcButtonKind.primary,
          onPressed: () {
            // Malformed JSON used to throw out of the button's callback and
            // land in the console with the dialog still open and nothing said.
            // A paste is exactly where bad input arrives, so it is answered
            // here instead.
            try {
              final decoded = jsonDecode(controller.text);
              Navigator.pop(
                context,
                DashboardDefinition.fromJson(
                    Map<String, dynamic>.from(decoded as Map)),
              );
            } catch (e) {
              error.value = 'That is not a page export: $e';
            }
          },
        ),
      ],
      child: ValueListenableBuilder<String?>(
        valueListenable: error,
        builder: (context, message, _) => _JsonField(
          controller: controller,
          label: 'Paste exported page JSON',
          error: message,
        ),
      ),
    ),
  );
  if (imported == null) return;
  await ref.read(dashboardsProvider.notifier).importDashboard(imported);
}

class _JsonField extends StatelessWidget {
  const _JsonField({
    required this.controller,
    required this.label,
    this.error,
  });

  final TextEditingController controller;
  final String label;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
        SizedBox(height: t.space.xs),
        Container(
          decoration: BoxDecoration(
            color: t.surface.sunken,
            borderRadius: BorderRadius.circular(t.radius.sm),
            border: Border.all(
              color: error == null ? t.stroke.hairline : t.accent.danger,
              width: t.stroke.width,
            ),
          ),
          padding: EdgeInsets.all(t.space.sm),
          child: TextField(
            controller: controller,
            maxLines: 18,
            // JSON is code: the mono ramp, not the prose one.
            style: t.text
                .resolve(t.text.bodySmall, mono: true)
                .copyWith(color: t.surface.onBase),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
            ),
          ),
        ),
        if (error != null) ...[
          SizedBox(height: t.space.xs),
          Text(error!,
              style: t.text.captionStyle.copyWith(color: t.accent.danger)),
        ],
      ],
    );
  }
}
