import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dashboard/code_runtime.dart';
import '../../design/tokens.dart';
import '../dashboard/code_card.dart';

/// Where a code element is actually written.
///
/// **Not in the inspector.** A 340px column is where you set a number, not
/// where you write a program — the config form's five-line textarea is the
/// shape that makes people paste code in from somewhere else and never edit it
/// again. This is the desktop-application answer: a surface with room to work
/// and the thing you are working on visible beside it.
///
/// **The preview is the real element**, sandbox and all, wired to the real
/// house — not a mock and not a snapshot. It is the same [CodeCard] the page
/// draws, so anything that works here works there, and the log beneath it is
/// the frame's own `homecore.log` and its uncaught errors. A card that silently
/// renders nothing is the worst thing this feature could ship, so the console
/// is present from the start rather than added after the first support
/// question.
///
/// Applying is explicit. Every keystroke rebuilding the document would restart
/// the author's own animations mid-sentence, so ⌘↵ (or the button) is what
/// hands the code over.
class CodeEditorSheet extends StatefulWidget {
  const CodeEditorSheet({
    super.key,
    required this.source,
    required this.config,
    this.title = 'Code',
    this.hint = 'HTML, SVG and script. `homecore.states`, '
        '`homecore.onUpdate(fn)`, `homecore.set(id, patch)`.',
    this.sourceKey = 'html',
    this.starter = codeStarter,
    this.preview,
  });

  /// What is stored today.
  final String source;

  /// The rest of the element's config — the device grant especially, because a
  /// preview that could see everything would teach the wrong thing about what
  /// the card will do on the page.
  final Map<String, dynamic> config;

  final String title;
  final String hint;

  /// Which config key the edited text belongs to. A bound drawing keeps its
  /// source under `svg` and generates `html` from it, so the preview has to be
  /// told which one it is editing.
  final String sourceKey;

  /// What an empty element is filled with, so the first thing anyone sees is a
  /// working example rather than a blank page.
  final String starter;

  /// How to draw the thing being edited. Null means the code element itself —
  /// the case this sheet was built for. A bound SVG passes its own card, so
  /// the preview shows the drawing *with its bindings applied* rather than the
  /// generated script.
  final Widget Function(
      Map<String, dynamic> config, ValueChanged<String> onLog)? preview;

  static Future<String?> open(
    BuildContext context, {
    required String source,
    required Map<String, dynamic> config,
    String title = 'Code',
    String? hint,
    String sourceKey = 'html',
    String starter = codeStarter,
    Widget Function(Map<String, dynamic> config, ValueChanged<String> onLog)?
        preview,
  }) =>
      showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CodeEditorSheet(
          source: source,
          config: config,
          title: title,
          hint: hint ??
              'HTML, SVG and script. `homecore.states`, '
                  '`homecore.onUpdate(fn)`, `homecore.set(id, patch)`.',
          sourceKey: sourceKey,
          starter: starter,
          preview: preview,
        ),
      );

  @override
  State<CodeEditorSheet> createState() => _CodeEditorSheetState();
}

class _CodeEditorSheetState extends State<CodeEditorSheet> {
  late final TextEditingController _controller = TextEditingController(
      text: widget.source.isEmpty ? codeStarter : widget.source);

  /// What the preview is running, as opposed to what is being typed.
  late String _applied = _controller.text;

  final _log = <String>[];

  bool get _dirty => _applied != _controller.text;

  void _apply() {
    setState(() {
      _applied = _controller.text;
      // The log belongs to the run, not to the session: lines from code that
      // no longer exists are worse than no lines at all.
      _log.clear();
    });
  }

  void _onLog(String line) {
    if (!mounted) return;
    setState(() {
      _log.add(line);
      // A loop that logs every frame would otherwise eat the session.
      if (_log.length > 100) _log.removeAt(0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: t.surface.base,
      insetPadding: EdgeInsets.all(t.space.lg),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radius.md)),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _apply,
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _apply,
        },
        child: Focus(
          autofocus: true,
          child: SizedBox(
            width: size.width * 0.9,
            height: size.height * 0.86,
            child: Column(
              children: [
                _Bar(
                  title: widget.title,
                  hint: widget.hint,
                  dirty: _dirty,
                  onApply: _apply,
                  onCancel: () => Navigator.of(context).pop(),
                  onSave: () => Navigator.of(context).pop(_controller.text),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _Editor(controller: _controller)),
                      Container(
                          width: t.stroke.width, color: t.stroke.hairline),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: Container(
                                color: t.surface.sunken,
                                padding: EdgeInsets.all(t.space.md),
                                // Keyed on the applied source so pressing Run
                                // tears the old document down rather than
                                // reusing a frame whose script has already run.
                                child: KeyedSubtree(
                                  key: ValueKey(_applied),
                                  child: widget.preview?.call(
                                        {
                                          ...widget.config,
                                          widget.sourceKey: _applied
                                        },
                                        _onLog,
                                      ) ??
                                      CodeCard(
                                        config: {
                                          ...widget.config,
                                          'html': _applied
                                        },
                                        onLog: _onLog,
                                      ),
                                ),
                              ),
                            ),
                            _Console(lines: _log),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.title,
    required this.hint,
    required this.dirty,
    required this.onApply,
    required this.onCancel,
    required this.onSave,
  });

  final String title;
  final String hint;
  final bool dirty;
  final VoidCallback onApply;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface.raised,
        border: Border(
            bottom:
                BorderSide(color: t.stroke.hairline, width: t.stroke.width)),
      ),
      padding:
          EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
      child: Row(
        children: [
          Text(title,
              style: t.text.subtitleStyle.copyWith(
                  color: t.surface.onBase, fontWeight: FontWeight.w600)),
          SizedBox(width: t.space.md),
          Expanded(
            child: Text(
              hint,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
            ),
          ),
          if (dirty)
            Padding(
              padding: EdgeInsets.only(right: t.space.sm),
              child: Text('Not running yet',
                  style: t.text.captionStyle.copyWith(color: t.accent.active)),
            ),
          TextButton(
            onPressed: onApply,
            child: Text(dirty ? 'Run  ⌘↵' : 'Run again'),
          ),
          SizedBox(width: t.space.xs),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          SizedBox(width: t.space.xs),
          FilledButton(onPressed: onSave, child: const Text('Done')),
        ],
      ),
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      color: t.surface.base,
      padding: EdgeInsets.all(t.space.md),
      child: TextField(
        controller: controller,
        maxLines: null,
        expands: true,
        autofocus: true,
        textAlignVertical: TextAlignVertical.top,
        // No syntax highlighting, deliberately: it wants a parser per language
        // in a document that is three of them at once. Monospace, a readable
        // size and room to work are what the five-line textarea was missing.
        //
        // Through the ramp with `mono: true`, never `fontFamily: 'monospace'`.
        // A family name the bundle does not carry resolves to no glyphs at all
        // on web, and the pane renders *empty* — this editor opened blank on
        // its first run for exactly that reason, and `plugin_runtimes_page`
        // had already been bitten by it once.
        style: t.text.resolve(t.text.bodySmall, mono: true).copyWith(
              color: t.surface.onBase,
              height: 1.45,
            ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }
}

/// What the element said, and what it threw.
class _Console extends StatelessWidget {
  const _Console({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      height: 132,
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.surface.base,
        border: Border(
            top: BorderSide(color: t.stroke.hairline, width: t.stroke.width)),
      ),
      padding: EdgeInsets.all(t.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CONSOLE',
              style:
                  t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.xs),
          Expanded(
            child: lines.isEmpty
                ? Text(
                    'Nothing yet. `homecore.log(…)` and any error land here.',
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted))
                : ListView.builder(
                    reverse: true,
                    itemCount: lines.length,
                    itemBuilder: (context, i) {
                      final line = lines[lines.length - 1 - i];
                      final bad = line.startsWith('Error') ||
                          line.startsWith('Refused');
                      return Text(
                        line,
                        style: t.text
                            .resolve(t.text.caption, mono: true)
                            .copyWith(
                              color:
                                  bad ? t.accent.danger : t.surface.onBaseMuted,
                            ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
