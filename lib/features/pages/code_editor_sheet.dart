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
  });

  /// What is stored today.
  final String source;

  /// The rest of the element's config — the device grant especially, because a
  /// preview that could see everything would teach the wrong thing about what
  /// the card will do on the page.
  final Map<String, dynamic> config;

  static Future<String?> open(
    BuildContext context, {
    required String source,
    required Map<String, dynamic> config,
  }) =>
      showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CodeEditorSheet(source: source, config: config),
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
                                child: CodeCard(
                                  // Keyed on the applied source so pressing
                                  // Run tears the old document down rather
                                  // than reusing a frame whose script has
                                  // already run.
                                  key: ValueKey(_applied),
                                  config: {...widget.config, 'html': _applied},
                                  onLog: _onLog,
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
    required this.dirty,
    required this.onApply,
    required this.onCancel,
    required this.onSave,
  });

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
          Text('Code',
              style: t.text.subtitleStyle.copyWith(
                  color: t.surface.onBase, fontWeight: FontWeight.w600)),
          SizedBox(width: t.space.md),
          Text(
            'HTML, SVG and script. `homecore.states`, `homecore.onUpdate(fn)`, '
            '`homecore.set(id, patch)`.',
            style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
          ),
          const Spacer(),
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
