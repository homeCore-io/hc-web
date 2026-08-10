import 'package:flutter/material.dart';

import '../../core/models/skin_document.dart';
import '../../core/devices/presentation.dart';
import '../../design/hc_icons.dart';
import '../../design/icon_sets.dart';
import '../../design/font_registry.dart';
import '../../design/skin_catalogue.dart';
import '../../design/tokens.dart';
import '../../core/api/assets_api.dart';
import '../assets/asset_field.dart';

/// The advanced disclosure: every derived value, overridable, with its rule.
///
/// Step 7 of `theme-editor-plan.md`, and the last thing the plan asks for. It
/// is deliberately *shut* by default and deliberately last on the page — the
/// seeds are how a skin is meant to be made, and a panel of forty-eight fields
/// offered first would make the derivation look like something to work around
/// rather than something to start from.
///
/// **A row exists to be closed again.** Every override shows the value it
/// replaced and a control to go back to it, so poking at one is reversible
/// without remembering what was there. The marker on an overridden row is not
/// decoration: with forty-eight rows and no marker, a skin that behaves oddly
/// gives you no way to find the two values someone changed a month ago.
///
/// **The panel lives in the left column.** It scrolls independently of the
/// preview, so the effect of an override is visible while you are scrolled to
/// the bottom of a long list — which is the only reason to put a live preview
/// beside an editor at all.
class SkinAdvanced extends StatefulWidget {
  const SkinAdvanced({
    super.key,
    required this.derived,
    required this.edited,
    required this.overrides,
    required this.onChanged,
  });

  /// The tokens the seeds produce, with no overrides applied — what a reset
  /// goes back to, and what each row reports as its origin.
  final HcTokens derived;

  /// The tokens actually in force, overrides and all.
  final HcTokens edited;

  final Map<String, String> overrides;

  /// The whole map, replaced. Handing back one key would leave the caller to
  /// work out whether it was a set or a clear.
  final ValueChanged<Map<String, String>> onChanged;

  @override
  State<SkinAdvanced> createState() => _SkinAdvancedState();
}

class _SkinAdvancedState extends State<SkinAdvanced> {
  bool _open = false;

  void _set(String path, String value) {
    final next = Map<String, String>.from(widget.overrides)..[path] = value;
    widget.onChanged(next);
  }

  void _reset(String path) {
    final next = Map<String, String>.from(widget.overrides)..remove(path);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final overridden =
        derivedTokens.where((d) => widget.overrides.containsKey(d.path)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(top: t.space.md),
          child: Container(height: t.stroke.width, color: t.stroke.hairline),
        ),
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: t.space.sm),
              child: Row(
                children: [
                  // Not '▸'/'▾'. The bundled Inter has no geometric shapes,
                  // so those render as tofu — the same trap the icon set
                  // exists to close.
                  Icon(_open ? HcIcons.caretDown : HcIcons.caretRight,
                      size: 12, color: t.surface.onBaseMuted),
                  SizedBox(width: t.space.xs),
                  Expanded(
                    child: Text(
                      'Advanced — ${derivedTokens.length} derived',
                      style: t.text.bodySmallStyle
                          .copyWith(color: t.surface.onBase),
                    ),
                  ),
                  // The count is the useful half of the summary: it says
                  // whether this skin has been hand-edited at all without
                  // opening anything.
                  if (overridden > 0)
                    Text('$overridden changed',
                        style: t.text.captionStyle
                            .copyWith(color: t.accent.active)),
                ],
              ),
            ),
          ),
        ),
        if (_open) ...[
          Padding(
            padding: EdgeInsets.only(bottom: t.space.sm),
            child: Text(
              'These are computed from the controls above. Change one here and '
              'it stops following them until you reset it.',
              style: t.text.captionStyle
                  .copyWith(color: t.surface.onBaseMuted, height: 1.4),
            ),
          ),
          _IconSetPicker(
            value: widget.overrides[iconSetOverrideKey] ??
                IconSets.builtIn.first.key,
            onChanged: (key) => key == IconSets.builtIn.first.key
                ? _reset(iconSetOverrideKey)
                : _set(iconSetOverrideKey, key),
          ),
          _Fonts(
            fonts: fontsFromOverrides(widget.overrides),
            onAdd: (family, url) => _set('$fontOverridePrefix$family', url),
            onRemove: (family) => _reset('$fontOverridePrefix$family'),
          ),
          for (final group in _groups())
            _Group(
              label: group,
              rows: [
                for (final d in derivedTokens.where((d) => d.group == group))
                  _Row(
                    key: ValueKey(d.path),
                    token: d,
                    derived: d.read(widget.derived),
                    current: d.read(widget.edited),
                    isOverridden: widget.overrides.containsKey(d.path),
                    onSet: (v) => _set(d.path, v),
                    onReset: () => _reset(d.path),
                  ),
              ],
            ),
        ],
      ],
    );
  }

  /// Group headings in catalogue order, without a Set losing that order.
  List<String> _groups() {
    final seen = <String>[];
    for (final d in derivedTokens) {
      if (!seen.contains(d.group)) seen.add(d.group);
    }
    return seen;
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.label, required this.rows});

  final String label;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: t.space.xs),
            child: Text(label.toUpperCase(),
                style: t.text.overlineStyle
                    .copyWith(color: t.surface.onBaseMuted)),
          ),
          ...rows,
        ],
      ),
    );
  }
}

/// One derived value: what it is, where it came from, and the way back.
class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.token,
    required this.derived,
    required this.current,
    required this.isOverridden,
    required this.onSet,
    required this.onReset,
  });

  final DerivedToken token;
  final Object derived;
  final Object current;
  final bool isOverridden;
  final ValueChanged<String> onSet;
  final VoidCallback onReset;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  late final TextEditingController _c =
      TextEditingController(text: formatTokenValue(widget.current));
  bool _bad = false;

  @override
  void didUpdateWidget(covariant _Row old) {
    super.didUpdateWidget(old);
    // Only when the value moved from somewhere else — a reset, or a seed
    // control upstream recomputing it. Rewriting on every keystroke would
    // fight the cursor.
    final text = formatTokenValue(widget.current);
    if (old.current != widget.current && _c.text != text) {
      _c.text = text;
      _bad = false;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool _valid(String raw) => switch (widget.token.kind) {
        TokenKind.colour => parseSkinColour(raw.trim()) != null,
        TokenKind.family => FontRegistry.instance.has(raw.trim()),
        TokenKind.number => double.tryParse(raw.trim()) != null,
      };

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final isColour = widget.token.kind == TokenKind.colour;
    final isFamily = widget.token.kind == TokenKind.family;

    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.isOverridden)
                Padding(
                  padding: EdgeInsets.only(right: t.space.xs / 2),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                        color: t.accent.active, shape: BoxShape.circle),
                  ),
                ),
              Expanded(
                child: Text(
                  widget.token.path,
                  style: t.text.resolve(t.text.caption, mono: true).copyWith(
                      color: widget.isOverridden
                          ? t.surface.onBase
                          : t.surface.onBaseMuted),
                ),
              ),
              if (widget.isOverridden)
                Semantics(
                  button: true,
                  label: 'Reset ${widget.token.path} to derived',
                  child: GestureDetector(
                    onTap: widget.onReset,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: t.space.xs),
                      child: Text(
                        'was ${formatTokenValue(widget.derived)} ↺',
                        style: t.text.captionStyle
                            .copyWith(color: t.accent.active),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: t.space.xs / 2),
          Row(
            children: [
              if (isColour) ...[
                Container(
                  width: 28,
                  height: 18,
                  decoration: BoxDecoration(
                    color: widget.current as Color,
                    borderRadius: BorderRadius.circular(t.radius.xs),
                    border: Border.all(
                        color: t.surface.onBaseMuted, width: t.stroke.width),
                  ),
                ),
                SizedBox(width: t.space.xs),
              ],
              if (isFamily)
                // A list, not a field. A name the app does not have falls back
                // to the engine's own face and sends glyph fallback to a CDN,
                // so the control cannot be one that lets you type it.
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: FontRegistry.instance.has('${widget.current}')
                        ? '${widget.current}'
                        : null,
                    isExpanded: true,
                    isDense: true,
                    style: t.text
                        .resolve(t.text.caption, mono: true)
                        .copyWith(color: t.surface.onBase),
                    decoration: const InputDecoration(
                        isDense: true, border: InputBorder.none),
                    items: [
                      for (final family in FontRegistry.instance.available)
                        DropdownMenuItem(
                            value: family,
                            child: Text(family,
                                style: TextStyle(fontFamily: family))),
                    ],
                    onChanged: (v) => v == null ? null : widget.onSet(v),
                  ),
                )
              else
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: t.surface.sunken,
                      borderRadius: BorderRadius.circular(t.radius.xs),
                      border: Border.all(
                          color: _bad ? t.accent.danger : t.stroke.hairline,
                          width: t.stroke.width),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: t.space.xs),
                    child: TextField(
                      controller: _c,
                      style: t.text
                          .resolve(t.text.caption, mono: true)
                          .copyWith(color: t.surface.onBase),
                      decoration: const InputDecoration(
                          isDense: true, border: InputBorder.none),
                      onChanged: (raw) {
                        final ok = _valid(raw);
                        setState(() => _bad = !ok);
                        if (ok) widget.onSet(raw.trim());
                      },
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: t.space.xs / 2),
          // The reason to open this panel. Someone who disagrees with an answer
          // can change it; someone who disagrees with the question has at least
          // been told what the question was.
          Text(
            // Always "from", overridden or not. The derivation is a fact about
            // the token whatever is currently in the field, and "was Success —
            // air quality reads as a verdict" reads as though the *value* had
            // been the word Success. Three other things on the row already say
            // it is overridden; a fourth that costs grammar is not worth it.
            'from ${widget.token.derivedFrom}',
            style: t.text.captionStyle
                .copyWith(color: t.surface.onBaseMuted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// The fonts this skin brings with it.
///
/// At the top of the panel because the family picker below is a dead control
/// until something is in here: the app ships two faces, and the whole point of
/// the ask was the third.
///
/// A family plus an address — or a file, now that core has somewhere to put
/// one. The stored shape never changed: a skin has always carried an address,
/// and an upload just fills it in for you.
class _Fonts extends StatefulWidget {
  const _Fonts({
    required this.fonts,
    required this.onAdd,
    required this.onRemove,
  });

  final Map<String, String> fonts;
  final void Function(String family, String url) onAdd;
  final ValueChanged<String> onRemove;

  @override
  State<_Fonts> createState() => _FontsState();
}

class _FontsState extends State<_Fonts> {
  final _family = TextEditingController();
  String _url = '';
  String? _note;

  @override
  void dispose() {
    _family.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final family = _family.text.trim();
    final url = _url.trim();
    if (family.isEmpty || url.isEmpty) return;
    // Loaded before it is stored. A skin carrying a font nobody can fetch is a
    // skin whose type controls quietly do nothing, and finding that out later
    // is worse than being told now.
    final ok = await FontRegistry.instance.register(family, url);
    if (!mounted) return;
    setState(() => _note = ok ? null : 'That did not load as a font.');
    if (ok) {
      widget.onAdd(family, url);
      _family.clear();
      setState(() => _url = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('FONTS',
              style:
                  t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.xs),
          for (final font in widget.fonts.entries)
            Padding(
              padding: EdgeInsets.only(bottom: t.space.xs / 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(font.key,
                        style: t.text.bodySmallStyle.copyWith(
                            color: t.surface.onBase, fontFamily: font.key)),
                  ),
                  if (!FontRegistry.instance.has(font.key))
                    Padding(
                      padding: EdgeInsets.only(right: t.space.xs),
                      child: Text('not loaded',
                          style: t.text.captionStyle
                              .copyWith(color: t.accent.danger)),
                    ),
                  Semantics(
                    button: true,
                    label: 'Remove ${font.key}',
                    child: GestureDetector(
                      onTap: () => widget.onRemove(font.key),
                      child: Icon(HcIcons.x,
                          size: 12, color: t.surface.onBaseMuted),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _family,
                  style:
                      t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
                  decoration: const InputDecoration(
                      isDense: true, hintText: 'Family name'),
                ),
              ),
              SizedBox(width: t.space.xs),
              TextButton(onPressed: _add, child: const Text('Add')),
            ],
          ),
          SizedBox(height: t.space.xs),
          // Two rows rather than three fields across a 340px pane. No preview:
          // a font has nothing to show at thumbnail size, and the panel above
          // already renders each family in its own face, which is the only
          // preview that means anything here.
          AssetField(
            value: _url,
            onChanged: (v) => setState(() => _url = v),
            kinds: fontExtensions,
            preview: false,
            hint: 'Address of the font file, or choose one',
          ),
          if (_note != null)
            Text(_note!,
                style: t.text.captionStyle.copyWith(color: t.accent.danger)),
          Text(
            'The family name must be the one inside the file. Fonts are '
            'fetched from your own house — nothing here reaches the internet.',
            style: t.text.captionStyle
                .copyWith(color: t.surface.onBaseMuted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// Which set of glyphs the house wears.
///
/// A row of samples rather than a list of names: nobody knows what "Phosphor"
/// looks like, and the difference between two icon sets is entirely visible
/// and not at all describable.
class _IconSetPicker extends StatelessWidget {
  const _IconSetPicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ICONS',
              style:
                  t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.xs),
          Row(
            children: [
              for (final set in IconSets.builtIn)
                Padding(
                  padding: EdgeInsets.only(right: t.space.xs),
                  child: Semantics(
                    button: true,
                    selected: set.key == value,
                    label: set.label,
                    child: GestureDetector(
                      onTap: () => onChanged(set.key),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: t.space.sm, vertical: t.space.xs),
                        decoration: BoxDecoration(
                          color: set.key == value ? t.surface.raised : null,
                          borderRadius: BorderRadius.circular(t.radius.sm),
                          border: Border.all(
                            color: set.key == value
                                ? t.accent.active
                                : t.stroke.hairline,
                            width: t.stroke.width,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // The sample is the control. Three facets that
                            // look different in different sets.
                            for (final facet in const [
                              DeviceFacet.light,
                              DeviceFacet.lock,
                              DeviceFacet.motion,
                            ])
                              Padding(
                                padding: EdgeInsets.only(right: t.space.xs / 2),
                                child: Icon(set.forFacet(facet),
                                    size: 15,
                                    color: set.key == value
                                        ? t.surface.onBase
                                        : t.surface.onBaseMuted),
                              ),
                            SizedBox(width: t.space.xs / 2),
                            Text(set.label,
                                style: t.text.captionStyle.copyWith(
                                    color: set.key == value
                                        ? t.surface.onBase
                                        : t.surface.onBaseMuted)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
