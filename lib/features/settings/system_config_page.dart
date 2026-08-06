import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/system_config_provider.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';
import '../plugins/config_descriptor/config_merge.dart';
import '../plugins/config_descriptor/descriptor.dart';
import '../plugins/config_descriptor/descriptor_renderer.dart';

/// `homecore.toml`, as a screen.
///
/// Deliberately *not* under `/admin`: that path still resolves to the
/// pre-redesign admin chrome. This is a Manage section like Plugins or Devices,
/// on the app-native shell.
///
/// It renders core's own config descriptor with the renderer the Plugin Studio
/// already uses — the same field kinds, the same conditionals, the same
/// controls. That is the whole point of describing the config server-side:
/// there is no second settings UI to write or to keep in step.
class SystemConfigPage extends ConsumerStatefulWidget {
  const SystemConfigPage({super.key});

  @override
  ConsumerState<SystemConfigPage> createState() => _SystemConfigPageState();
}

class _SystemConfigPageState extends ConsumerState<SystemConfigPage> {
  String? _sectionId;
  String _search = '';
  bool _raw = false;
  bool _saving = false;
  String? _error;

  /// Set by a save that core said needs a restart. Sticky until the restart
  /// happens: the change is in the file but not in the running process, and
  /// nothing else on screen would say so.
  bool _restartRequired = false;
  bool _restarting = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(systemConfigProvider);

    return SectionScaffold(
      title: 'Configuration',
      subtitle: async.value?.config.path,
      stats: [
        if (async.value != null)
          SectionStat(
            value: '${async.value!.descriptor.sections.length}',
            label: 'sections',
          ),
        if (_restartRequired)
          const SectionStat(
              value: 'Restart', label: 'pending', tone: SectionTone.warn),
      ],
      actions: [
        Builder(builder: (context) {
          final t = HcTokens.of(context);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ViewToggle(
                raw: _raw,
                onChanged: (v) => setState(() => _raw = v),
              ),
              SizedBox(width: t.space.sm),
              IconButton(
                icon: Icon(Icons.refresh, color: t.surface.onBaseMuted),
                tooltip: 'Reload from disk',
                onPressed: () =>
                    ref.read(systemConfigProvider.notifier).reload(),
              ),
            ],
          );
        }),
      ],
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Error('$e'),
        data: (bundle) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_restartRequired)
              _RestartBanner(
                restarting: _restarting,
                onRestart: () => _restart(),
              ),
            if (_error != null) _SaveError(_error!),
            Expanded(
              child: _raw
                  ? _RawEditor(
                      initial: bundle.config.raw,
                      saving: _saving,
                      onSave: _saveRaw,
                    )
                  : _Form(
                      bundle: bundle,
                      sectionId:
                          _sectionId ?? bundle.descriptor.sections.first.id,
                      search: _search,
                      saving: _saving,
                      onSection: (id) => setState(() => _sectionId = id),
                      onSearch: (q) => setState(() => _search = q),
                      onSave: _savePatch,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Save only what changed.
  ///
  /// The renderer hands back the whole document; `diffConfig` reduces it to the
  /// sections and fields that actually differ, which is what core's patch mode
  /// wants. Sending the document whole would rewrite every value in the file
  /// and lose nothing visible — until two people edit at once, or a comment
  /// matters.
  Future<void> _savePatch(
    ConfigDescriptor _,
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) async {
    final patch = diffConfig(before, after);
    if (patch.isEmpty) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref.read(systemConfigApiProvider).patch(patch);
      if (result.restartRequired && mounted) {
        setState(() => _restartRequired = true);
      }
      await ref.read(systemConfigProvider.notifier).reload();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveRaw(String text) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref.read(systemConfigApiProvider).putRaw(text);
      if (result.restartRequired && mounted) {
        setState(() => _restartRequired = true);
      }
      await ref.read(systemConfigProvider.notifier).reload();
    } catch (e) {
      // A TOML syntax error comes back as 422 with the parser's message. It is
      // the most useful thing on the screen — core refused the write, so the
      // file on disk is still good.
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Restart core, then wait for it to answer again.
  ///
  /// The request itself will not get a clean reply — the process goes down
  /// while writing it — so a failure here is expected and ignored. What matters
  /// is the poll afterwards.
  Future<void> _restart() async {
    final api = ref.read(systemConfigApiProvider);
    setState(() => _restarting = true);
    try {
      await api.restart();
    } catch (_) {
      // Expected: the connection drops mid-response.
    }
    for (var attempt = 0; attempt < 40; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 750));
      if (!mounted) return;
      if (await api.isUp()) {
        if (!mounted) return;
        setState(() {
          _restarting = false;
          _restartRequired = false;
        });
        await ref.read(systemConfigProvider.notifier).reload();
        return;
      }
    }
    if (mounted) {
      setState(() {
        _restarting = false;
        _error = 'Core did not come back within 30 seconds. '
            'Check the server before changing anything else.';
      });
    }
  }
}

// ── form view ───────────────────────────────────────────────────────────────

class _Form extends StatelessWidget {
  const _Form({
    required this.bundle,
    required this.sectionId,
    required this.search,
    required this.saving,
    required this.onSection,
    required this.onSearch,
    required this.onSave,
  });

  final SystemConfigBundle bundle;
  final String sectionId;
  final String search;
  final bool saving;
  final ValueChanged<String> onSection;
  final ValueChanged<String> onSearch;
  final Future<void> Function(
      ConfigDescriptor, Map<String, dynamic>, Map<String, dynamic>) onSave;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final sections = bundle.descriptor.sections;
    final matches = _matching(sections, search);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 232,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                    t.space.lg, t.space.sm, t.space.md, t.space.sm),
                child: TextField(
                  onChanged: onSearch,
                  style: t.text.bodyStyle,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Search settings',
                    prefixIcon: Icon(Icons.search, size: 16),
                    prefixIconConstraints:
                        BoxConstraints(minWidth: 34, minHeight: 30),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.only(
                      left: t.space.md, right: t.space.sm, bottom: t.space.lg),
                  children: [
                    for (final s in matches)
                      _RailEntry(
                        title: s.title,
                        selected: s.id == sectionId,
                        onTap: () => onSection(s.id),
                      ),
                    if (matches.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(t.space.sm),
                        child: Text(
                          'Nothing matches “$search”.',
                          style: t.text.bodySmallStyle
                              .copyWith(color: t.surface.onBaseMuted),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: t.stroke.hairline),
        Expanded(
          child: ConfigDescriptorRenderer(
            key: ValueKey('cfg-$sectionId'),
            descriptor: bundle.descriptor,
            initialValues: bundle.config.parsed,
            onlySectionId: matches.any((s) => s.id == sectionId)
                ? sectionId
                : (matches.isNotEmpty ? matches.first.id : sectionId),
            saving: saving,
            onSave: (values, _) =>
                onSave(bundle.descriptor, bundle.config.parsed, values),
          ),
        ),
      ],
    );
  }

  /// Search matches a section by its own title *or* by any field in it — with
  /// 82 fields across 19 sections, remembering which section holds `ring
  /// buffer` is not reasonable.
  static List<CfgSection> _matching(List<CfgSection> sections, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return sections;
    return [
      for (final s in sections)
        if (s.title.toLowerCase().contains(q) ||
            s.fields.any((f) =>
                (f.label ?? '').toLowerCase().contains(q) ||
                (f.key ?? '').toLowerCase().contains(q) ||
                (f.help ?? '').toLowerCase().contains(q)))
          s,
    ];
  }
}

class _RailEntry extends StatelessWidget {
  const _RailEntry(
      {required this.title, required this.selected, required this.onTap});

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(t.radius.sm),
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.sm),
        child: Text(
          title,
          style: t.text.bodyStyle.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? t.surface.onBase : t.surface.onBaseMuted),
        ),
      ),
    );
  }
}

// ── raw view ────────────────────────────────────────────────────────────────

/// The whole file in a text box.
///
/// Kept because a form can only edit what the descriptor describes, and the
/// descriptor will always trail the config by a release or two. It is also how
/// you fix a file the form cannot express — a commented-out block, a section
/// core has not learned yet.
class _RawEditor extends StatefulWidget {
  const _RawEditor({
    required this.initial,
    required this.saving,
    required this.onSave,
  });

  final String initial;
  final bool saving;
  final Future<void> Function(String) onSave;

  @override
  State<_RawEditor> createState() => _RawEditorState();
}

class _RawEditorState extends State<_RawEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  late String _saved = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final dirty = _controller.text != _saved;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                t.space.lg, t.space.sm, t.space.lg, t.space.sm),
            child: TextField(
              controller: _controller,
              onChanged: (_) => setState(() {}),
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: t.text.resolve(t.text.bodySmall, mono: true),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(t.space.lg, 0, t.space.lg, t.space.md),
          child: Row(
            children: [
              Text(
                dirty ? 'Unsaved changes' : 'Saved',
                style: t.text.bodySmallStyle.copyWith(
                    color: dirty ? t.accent.warn : t.surface.onBaseMuted),
              ),
              const Spacer(),
              TextButton(
                onPressed: dirty && !widget.saving
                    ? () => setState(() => _controller.text = _saved)
                    : null,
                child: const Text('Discard'),
              ),
              SizedBox(width: t.space.sm),
              FilledButton(
                onPressed: dirty && !widget.saving
                    ? () async {
                        final text = _controller.text;
                        await widget.onSave(text);
                        if (mounted) setState(() => _saved = text);
                      }
                    : null,
                child: Text(widget.saving ? 'Saving…' : 'Save file'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── chrome ──────────────────────────────────────────────────────────────────

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.raw, required this.onChanged});
  final bool raw;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: BorderRadius.circular(t.radius.pill),
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, isRaw) in [('Form', false), ('TOML', true)])
            GestureDetector(
              onTap: () => onChanged(isRaw),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: raw == isRaw ? t.surface.overlay : null,
                  borderRadius: BorderRadius.circular(t.radius.pill),
                ),
                child: Text(
                  label,
                  style: t.text.bodySmallStyle.copyWith(
                      fontWeight: FontWeight.w600,
                      color: raw == isRaw
                          ? t.surface.onBase
                          : t.surface.onBaseMuted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RestartBanner extends StatelessWidget {
  const _RestartBanner({required this.restarting, required this.onRestart});
  final bool restarting;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      margin: EdgeInsets.fromLTRB(t.space.lg, t.space.sm, t.space.lg, 0),
      padding:
          EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
      decoration: BoxDecoration(
        color: t.accent.warn.withValues(alpha: 0.10),
        border: Border.all(color: t.accent.warn.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(t.radius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: t.accent.warn),
          SizedBox(width: t.space.sm),
          Expanded(
            child: Text(
              restarting
                  ? 'Restarting core — waiting for it to answer again…'
                  : 'Saved to the file. Core is still running the old settings '
                      'until it restarts.',
              style: t.text.bodyStyle.copyWith(color: t.surface.onBase),
            ),
          ),
          if (restarting)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            FilledButton(
              onPressed: onRestart,
              child: const Text('Restart now'),
            ),
        ],
      ),
    );
  }
}

class _SaveError extends StatelessWidget {
  const _SaveError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      margin: EdgeInsets.fromLTRB(t.space.lg, t.space.sm, t.space.lg, 0),
      padding:
          EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
      decoration: BoxDecoration(
        color: t.accent.danger.withValues(alpha: 0.10),
        border: Border.all(color: t.accent.danger.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(t.radius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: t.accent.danger),
          SizedBox(width: t.space.sm),
          Expanded(
            child: SelectableText(
              message,
              style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
            ),
          ),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final forbidden = message.contains('403') || message.contains('admin');
    return Center(
      child: Padding(
        padding: EdgeInsets.all(t.space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(forbidden ? Icons.lock_outline : Icons.error_outline,
                size: 30, color: t.accent.danger),
            SizedBox(height: t.space.sm),
            Text(
              forbidden
                  ? 'Configuration is admin-only'
                  : 'Could not read the configuration',
              style: t.text.subtitleStyle.copyWith(color: t.surface.onBase),
            ),
            const SizedBox(height: 4),
            Text(
              forbidden
                  ? 'It names every path and port of this deployment.'
                  : message,
              textAlign: TextAlign.center,
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted),
            ),
          ],
        ),
      ),
    );
  }
}
