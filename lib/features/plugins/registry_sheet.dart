import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/registry_plugin.dart';
import '../../core/providers/plugins_provider.dart';
import '../../design/hc_icons.dart';
import '../../design/skins.dart';
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
    child: Theme(
      data: hcTheme(HcSkin.midnight),
      child: const _RegistrySheet(),
    ),
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

  Future<void> _install(RegistryPlugin p, {String? version}) async {
    final messenger = ScaffoldMessenger.of(context);
    final upgrade = version != null;
    setState(() {
      _installing = p.id;
      _error = null;
    });
    try {
      await ref
          .read(pluginsApiProvider)
          .installFromRegistry(p.id, version: version);
      ref.invalidate(pluginsProvider);
      ref.invalidate(registryPluginsProvider);
      messenger.showSnackBar(SnackBar(
          content:
              Text('${upgrade ? 'Updated' : 'Installed'} ${p.displayName}')));
    } catch (e) {
      setState(() => _error = '${upgrade ? 'Update' : 'Install'} failed: $e');
    } finally {
      if (mounted) setState(() => _installing = null);
    }
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
      for (final p in (installed.valueOrNull ?? const []))
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
                  style: TextStyle(
                      color: t.surface.onBase,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
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
                style: TextStyle(color: t.accent.danger, fontSize: 12.5)),
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
                      style: TextStyle(
                          color: t.surface.onBase,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600)),
                ),
                if (p.latest != null) ...[
                  const SizedBox(width: 8),
                  Text('v${p.latest}',
                      style: TextStyle(
                          color: t.surface.onBaseMuted,
                          fontSize: 12,
                          fontFeatures: t.numericFontFeatures)),
                ],
              ]),
              if (p.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(p.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: t.surface.onBaseMuted, fontSize: 12.5)),
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
            style: TextStyle(
                color: t.accent.active,
                fontSize: 12.5,
                fontWeight: FontWeight.w600)),
      ]);
    }
    return _filledButton(
        t, 'Install', _installing != null ? null : () => _install(p));
  }

  Widget _empty(HcTokens t, String title, String sub) => Padding(
        padding: EdgeInsets.all(t.space.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(HcIcons.plugins,
              size: 32, color: t.surface.onBaseMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(
                  color: t.surface.onBase,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(sub,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12.5)),
        ]),
      );
}
