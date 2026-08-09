import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/registry_plugin.dart';
import '../../core/api/plugin_runtimes_api.dart';
import '../../core/providers/plugin_runtimes_provider.dart';
import '../../core/providers/plugins_provider.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../../shell/hc_sheet.dart';

/// Browse the remote registry and install a plugin — the catalog behind the
/// "Add plugin" button. Install goes straight through the API (core resolves,
/// downloads, verifies, installs, and activates); the row shows a spinner until
/// it's done, then flips to "Installed".
Future<void> showRegistrySheet(BuildContext context, WidgetRef ref) {
  return showHcSheet(
    context,
    title: 'Add plugin',
    child: const _RegistrySheet(),
  );
}

class _RegistrySheet extends ConsumerStatefulWidget {
  const _RegistrySheet();
  @override
  ConsumerState<_RegistrySheet> createState() => _RegistrySheetState();
}

class _RegistrySheetState extends ConsumerState<_RegistrySheet> {
  String? _installing;
  String? _error;

  Future<void> _install(RegistryPlugin p,
      {String? version, String? runtimeId}) async {
    final messenger = ScaffoldMessenger.of(context);
    final upgrade = version != null;
    setState(() {
      _installing = p.id;
      _error = null;
    });
    try {
      final result = await ref
          .read(pluginsApiProvider)
          .installFromRegistry(p.id, version: version, runtimeId: runtimeId);

      // A plugin bound for a runtime is *placed*, not installed here: the
      // runtime fetches and starts it on its next reconcile, so there is
      // nothing local to settle and waiting for one would time out.
      final placedOn = result['placed_on'] as String?;
      if (placedOn != null) {
        ref.invalidate(pluginPlacementsProvider);
        messenger.showSnackBar(SnackBar(
            content: Text('${p.displayName} placed on '
                '${_runtimeLabel(placedOn)} — it starts there shortly')));
      } else {
        ref.invalidate(registryPluginsProvider);
        await ref.read(pluginsProvider.notifier).settle(p.id);
        messenger.showSnackBar(SnackBar(
            content:
                Text('${upgrade ? 'Updated' : 'Installed'} ${p.displayName}')));
      }
    } on DioException catch (e) {
      // 409 is core saying the choice is the operator's, and it names the
      // candidates. Asking is the whole answer — picking one for them would
      // put a plugin somewhere they did not intend and would not think to
      // check.
      final body = e.response?.data;
      final candidates = body is Map
          ? (body['runtimes'] as List?)?.map((r) => '$r').toList()
          : null;
      if (e.response?.statusCode == 409 && candidates != null) {
        if (mounted) setState(() => _installing = null);
        final chosen = await _askWhichRuntime(p, candidates);
        if (chosen != null) {
          await _install(p, version: version, runtimeId: chosen);
        }
        return;
      }
      final message = body is Map ? body['error'] ?? '$e' : '$e';
      setState(
          () => _error = '${upgrade ? 'Update' : 'Install'} failed: $message');
    } catch (e) {
      setState(() => _error = '${upgrade ? 'Update' : 'Install'} failed: $e');
    } finally {
      if (mounted) setState(() => _installing = null);
    }
  }

  /// Name a runtime the way the operator sees it elsewhere.
  String _runtimeLabel(String runtimeId) {
    final runtimes = ref.read(pluginRuntimesProvider).value ?? const [];
    for (final r in runtimes) {
      if (r.runtimeId == runtimeId) {
        return r.hostname.isEmpty ? r.runtimeId : r.hostname;
      }
    }
    return runtimeId;
  }

  Future<String?> _askWhichRuntime(
      RegistryPlugin p, List<String> candidates) async {
    final t = HcTokens.of(context);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: t.surface.raised,
        title: Text('Where should ${p.displayName} run?',
            style: t.text.subtitleStyle.copyWith(color: t.surface.onBase)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('More than one runtime can host it.',
                style: t.text.bodySmallStyle
                    .copyWith(color: t.surface.onBaseMuted)),
            SizedBox(height: t.space.sm),
            for (final id in candidates)
              ListTile(
                dense: true,
                title: Text(_runtimeLabel(id),
                    style: t.text.bodyStyle.copyWith(color: t.surface.onBase)),
                subtitle: Text(id,
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted)),
                onTap: () => Navigator.of(context).pop(id),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final catalog = ref.watch(registryPluginsProvider);
    // Which plugins are installed decides whether a row offers Install or
    // reports Installed. An empty map is not "none installed", it is "not
    // known yet" — rendering it as the former invites installing something
    // that is already there, so the list waits for the real answer.
    final installed = ref.watch(pluginsProvider);
    final installedVersions = <String, String?>{
      for (final p in (installed.value ?? const []))
        p.pluginId: p.installedVersion,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(t.space.md, t.space.md, t.space.sm, 0),
          child: Row(children: [
            Expanded(
              child: Text('Add plugin',
                  style: t.text.titleStyle.copyWith(
                      color: t.surface.onBase, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              icon: Icon(HcIcons.x, size: 18, color: t.surface.onBaseMuted),
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ]),
        ),
        Divider(height: 1, color: t.stroke.hairline),
        if (_error != null)
          Padding(
            padding: EdgeInsets.fromLTRB(t.space.md, t.space.sm, t.space.md, 0),
            child: Text(_error!,
                style: t.text.bodySmallStyle.copyWith(color: t.accent.danger)),
          ),
        Flexible(
          child: catalog.when(
            loading: () => const SizedBox(
                height: 220, child: Center(child: CircularProgressIndicator())),
            error: (_, __) => _empty(t, 'No registry available',
                'Set [registry] (url + public_key) in homecore config to browse and install plugins.'),
            data: (plugins) => !installed.hasValue
                ? const SizedBox(
                    height: 220,
                    child: Center(child: CircularProgressIndicator()))
                : plugins.isEmpty
                    ? _empty(
                        t, 'Registry is empty', 'No plugins are published yet.')
                    : ListView.separated(
                        padding: EdgeInsets.all(t.space.md),
                        itemCount: plugins.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _row(t, plugins[i], installedVersions),
                      ),
          ),
        ),
      ],
    );
  }

  Widget _row(
      HcTokens t, RegistryPlugin p, Map<String, String?> installedVersions) {
    final installed = installedVersions.containsKey(p.id);
    final installedVer = installedVersions[p.id];
    final updateAvailable =
        installed && p.latest != null && p.latest != installedVer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: t.radius.smR,
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Row(children: [
        Icon(HcIcons.plugins, size: 20, color: t.surface.onBaseMuted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Flexible(
                  child: Text(p.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.text.subtitleStyle.copyWith(
                          color: t.surface.onBase,
                          fontWeight: FontWeight.w600)),
                ),
                if (p.latest != null) ...[
                  const SizedBox(width: 8),
                  Text('v${p.latest}',
                      style: t.text.bodySmallStyle.copyWith(
                          color: t.surface.onBaseMuted,
                          fontFeatures: t.numericFontFeatures)),
                ],
              ]),
              if (p.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(p.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.text.bodySmallStyle
                          .copyWith(color: t.surface.onBaseMuted)),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _action(t, p, installed, updateAvailable),
      ]),
    );
  }

  Widget _filledButton(HcTokens t, String label, VoidCallback? onPressed) =>
      FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: t.accent.active,
          foregroundColor: t.accent.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label),
      );

  Widget _action(
      HcTokens t, RegistryPlugin p, bool installed, bool updateAvailable) {
    if (_installing == p.id) {
      return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (updateAvailable) {
      return _filledButton(t, 'Update to v${p.latest}',
          _installing != null ? null : () => _install(p, version: p.latest));
    }
    if (installed) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(HcIcons.check, size: 13, color: t.accent.active),
        const SizedBox(width: 5),
        Text('Installed',
            style: t.text.bodySmallStyle
                .copyWith(color: t.accent.active, fontWeight: FontWeight.w600)),
      ]);
    }
    // Three cases once runtimes exist, and the third is the one that matters:
    // a plugin no enrolled runtime can host is still a real plugin, and hiding
    // it would leave an operator wondering why the catalogue is missing
    // something they read about.
    if (p.needsRuntime(p.latest)) {
      final hosts = _hostsFor(p);
      if (hosts.isEmpty) {
        final needs = p.runtimeArtifacts(p.latest);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'Needs a ${needs.isEmpty ? 'runtime' : needs.first.runtime} runtime',
                style: t.text.bodySmallStyle
                    .copyWith(color: t.surface.onBaseMuted)),
            InkWell(
              onTap: () {
                Navigator.of(context).maybePop();
                context.go('/admin/plugin-runtimes');
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Enrol one',
                    style:
                        t.text.captionStyle.copyWith(color: t.accent.primary)),
              ),
            ),
          ],
        );
      }
      // One match installs without asking; several are the operator's choice,
      // and core is the one that says so — the label just sets the
      // expectation before the click.
      final label = hosts.length == 1
          ? 'Install on ${_runtimeLabel(hosts.first.runtimeId)}'
          : 'Install…';
      return _filledButton(
          t, label, _installing != null ? null : () => _install(p));
    }

    return _filledButton(
        t, 'Install', _installing != null ? null : () => _install(p));
  }

  /// Enrolled runtimes that could host this plugin's newest version.
  ///
  /// Mirrors core's matching rather than replacing it: core still decides, and
  /// a disagreement shows up as its refusal rather than as a silently wrong
  /// install. This exists so a row can say where something will go before
  /// anyone clicks.
  List<PluginRuntimeSummary> _hostsFor(RegistryPlugin p) {
    final runtimes = ref.watch(pluginRuntimesProvider).value ?? const [];
    final arts = p.runtimeArtifacts(p.latest);
    return runtimes
        .where((r) =>
            r.isApproved &&
            arts.any((a) =>
                a.runtime == r.kind && a.abi == r.abi && a.arch == r.arch))
        .toList();
  }

  Widget _empty(HcTokens t, String title, String sub) => Padding(
        padding: EdgeInsets.all(t.space.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(HcIcons.plugins,
              size: 32, color: t.surface.onBaseMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(title,
              style: t.text.subtitleStyle.copyWith(
                  color: t.surface.onBase, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(sub,
              textAlign: TextAlign.center,
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted)),
        ]),
      );
}
