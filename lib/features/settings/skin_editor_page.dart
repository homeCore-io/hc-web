import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/skin_document.dart';
import '../../core/providers/skins_provider.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/components/hc_surface.dart';
import '../../design/hc_icons.dart';
import '../../design/skin_resolve.dart';
import 'skin_advanced.dart';
import '../../design/skin_seeds.dart';
import '../../design/skin_validator.dart';
import '../../design/skins.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';

/// Editing a skin, with the app's own ratchets watching.
///
/// Step 6 of `theme-editor-plan.md`, and the piece the rest was for. Twelve
/// controls drive the ~26 seeds; `deriveTokens` turns those into all 74 tokens;
/// the preview renders real components in real states from exactly those
/// tokens; and `validateSkin` — the same function CI runs against the shipped
/// four — measures the result on every change.
///
/// **The live report is the signature bet.** A validator that answers at save
/// time tells you that you wasted the last ten minutes. This one names the
/// failing pair and its measured number while your hand is still on the
/// control: *"`active` is 1.80 : 1 against the card surface — needs 4.5."*
///
/// **The two skins must not leak into each other.** The chrome around the
/// preview is the app's current skin; the preview is the skin being edited.
/// One nested `Theme` separates them, and the acceptance bar calls this the
/// hard part of the page — it is hard to *notice*, not hard to do, because a
/// leak looks like a slightly wrong colour rather than like a bug.
///
/// **No typeface control.** The plan lists one, but hc-web self-hosts its fonts
/// and ships exactly one text family; a dropdown with a single entry is a
/// control that cannot be wrong. It arrives when a second family does.
class SkinEditorPage extends ConsumerStatefulWidget {
  const SkinEditorPage({super.key, required this.skinId});

  final String skinId;

  @override
  ConsumerState<SkinEditorPage> createState() => _SkinEditorPageState();
}

class _SkinEditorPageState extends ConsumerState<SkinEditorPage> {
  SkinSeeds? _draft;
  Map<String, String> _overrides = const {};
  String _name = '';
  String _base = 'midnight';
  bool _saving = false;
  bool _dirty = false;

  /// Loads the working copy once. Re-reading on every build would throw away
  /// an edit each time the skins list refreshed underneath.
  void _ensureLoaded(List<SkinDocument> skins) {
    if (_draft != null) return;
    final doc = skins.where((s) => s.id == widget.skinId).firstOrNull;
    if (doc == null) return;
    _draft = doc.toSeeds();
    _overrides = Map<String, String>.from(doc.overrides);
    _name = doc.name;
    _base = doc.base;
  }

  void _edit(SkinSeeds Function(SkinSeeds) change) {
    setState(() {
      _draft = change(_draft!);
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final seeds = _draft;
    if (seeds == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(skinsApiProvider).updateSkin(SkinDocument(
            id: widget.skinId,
            name: _name,
            base: _base,
            seeds: seedsToJson(seeds),
            overrides: _overrides,
          ));
      await ref.read(skinsProvider.notifier).reload();
      if (mounted) setState(() => _dirty = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final skins = ref.watch(skinsProvider).value ?? const <SkinDocument>[];
    _ensureLoaded(skins);

    final seeds = _draft;
    if (seeds == null) {
      return SectionScaffold(
        title: 'Skin',
        subtitle: 'Not found',
        child: Center(
          child: Text('That skin is not here any more.',
              style: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted)),
        ),
      );
    }

    // Everything downstream reads from this one derivation, so the preview and
    // the report can never disagree about what is being edited. `derived` is
    // kept separately because the advanced panel needs the value each override
    // replaced — that is what "reset to derived" resets to.
    final derived = deriveTokens(seeds);
    final edited = applySkinOverrides(derived, _overrides);
    final report = validateSkin(edited);

    return SectionScaffold(
      title: _name,
      subtitle: 'Made from ${_baseLabel(_base)}',
      child: LayoutBuilder(
        builder: (context, c) {
          final controls = _Controls(
            seeds: seeds,
            onEdit: _edit,
            saving: _saving,
            dirty: _dirty,
            onSave: _save,
            canSave: report.canSave,
            advanced: SkinAdvanced(
              derived: derived,
              edited: edited,
              overrides: _overrides,
              onChanged: (next) => setState(() {
                _overrides = next;
                _dirty = true;
              }),
            ),
          );
          final preview = _PreviewPane(tokens: edited, report: report);

          // Side by side where there is room; stacked where there is not, with
          // the preview first — on a phone the thing you are judging matters
          // more than the controls you scroll to.
          if (c.maxWidth < 900) {
            return ListView(
              padding: EdgeInsets.fromLTRB(
                  t.space.lg, t.space.sm, t.space.lg, t.space.xl),
              children: [preview, SizedBox(height: t.space.lg), controls],
            );
          }
          return Padding(
            padding: EdgeInsets.fromLTRB(
                t.space.lg, t.space.sm, t.space.lg, t.space.xl),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                    width: 340, child: SingleChildScrollView(child: controls)),
                SizedBox(width: t.space.lg),
                Expanded(child: SingleChildScrollView(child: preview)),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _baseLabel(String base) => switch (base) {
      'midnight' => 'Midnight',
      'ambient_glass' => 'Ambient Glass',
      'control_room' => 'Control Room',
      'soft_home' => 'Soft Home',
      _ => base,
    };

// ---------------------------------------------------------------------------
// The controls
// ---------------------------------------------------------------------------

class _Controls extends StatelessWidget {
  const _Controls({
    required this.seeds,
    required this.onEdit,
    required this.saving,
    required this.dirty,
    required this.onSave,
    required this.canSave,
    required this.advanced,
  });

  final SkinSeeds seeds;
  final void Function(SkinSeeds Function(SkinSeeds)) onEdit;
  final bool saving;
  final bool dirty;
  final VoidCallback onSave;
  final bool canSave;

  /// Last on the page, and shut by default. The seeds are how a skin is meant
  /// to be made; a panel of forty-eight fields offered first would make the
  /// derivation look like something to work around.
  final Widget advanced;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Group(label: 'Colour', children: [
          _ColourRow(
              label: 'Ground',
              value: seeds.ground,
              onChanged: (c) => onEdit((s) => s.copyWith(ground: c))),
          _ColourRow(
              label: 'Ink',
              value: seeds.ink,
              onChanged: (c) => onEdit((s) => s.copyWith(ink: c))),
          _ColourRow(
              label: 'Accent',
              value: seeds.accent,
              onChanged: (c) => onEdit((s) => s.copyWith(accent: c))),
          _ColourRow(
              label: 'Active',
              value: seeds.active,
              onChanged: (c) => onEdit((s) => s.copyWith(active: c))),
        ]),
        _Group(label: 'Faults', children: [
          _ColourRow(
              label: 'Success',
              value: seeds.success,
              onChanged: (c) => onEdit((s) => s.copyWith(success: c))),
          _ColourRow(
              label: 'Warn',
              value: seeds.warn,
              onChanged: (c) => onEdit((s) => s.copyWith(warn: c))),
          _ColourRow(
              label: 'Danger',
              value: seeds.danger,
              onChanged: (c) => onEdit((s) => s.copyWith(danger: c))),
        ]),
        _Group(label: 'Shape', children: [
          _SliderRow(
            label: 'Corners',
            value: seeds.corners.$3,
            min: 0,
            max: 32,
            format: (v) => '${v.round()}px',
            // One handle for all four — see `scaleCorners`.
            onChanged: (v) =>
                onEdit((s) => s.copyWith(corners: scaleCorners(s.corners, v))),
          ),
          _SliderRow(
            label: 'Spacing',
            value: seeds.spaceUnit,
            min: 4,
            max: 14,
            format: (v) => '${v.round()}px',
            onChanged: (v) =>
                onEdit((s) => s.copyWith(spaceUnit: v.roundToDouble())),
          ),
          _SliderRow(
            label: 'Type scale',
            value: seeds.typeScale,
            min: 0.8,
            max: 1.4,
            format: (v) => v.toStringAsFixed(2),
            onChanged: (v) => onEdit((s) => s.copyWith(typeScale: v)),
          ),
          _SliderRow(
            label: 'Glow',
            value: seeds.glowStrength,
            min: 0,
            max: 1,
            format: (v) => v.toStringAsFixed(2),
            // Radius follows strength: a skin at zero has no halo to give a
            // reach to, and core rejects the pair as a contradiction.
            onChanged: (v) => onEdit((s) => s.copyWith(
                  glowStrength: v,
                  glowRadius: v == 0 ? 0 : (s.glowRadius == 0 ? 30 : null),
                )),
          ),
        ]),
        _Group(label: 'Feel', children: [
          _ChoiceRow<Brightness>(
            label: 'Brightness',
            value: seeds.brightness,
            options: const {Brightness.dark: 'Dark', Brightness.light: 'Light'},
            onChanged: (v) => onEdit((s) => s.copyWith(brightness: v)),
          ),
          _ChoiceRow<SkinDensity>(
            label: 'Density',
            value: seeds.density,
            options: const {
              SkinDensity.compact: 'Compact',
              SkinDensity.comfortable: 'Comfortable',
              SkinDensity.wall: 'Wall',
            },
            onChanged: (v) => onEdit((s) => s.copyWith(density: v)),
          ),
          _ChoiceRow<SkinMotion>(
            label: 'Motion',
            value: seeds.motion,
            options: const {
              SkinMotion.crisp: 'Crisp',
              SkinMotion.standard: 'Standard',
              SkinMotion.calm: 'Calm',
            },
            onChanged: (v) => onEdit((s) => s.copyWith(motion: v)),
          ),
          _ChoiceRow<SkinGlass>(
            label: 'Glass',
            value: seeds.glass,
            options: const {
              SkinGlass.none: 'None',
              SkinGlass.tinted: 'Tinted',
              SkinGlass.frosted: 'Frosted',
            },
            onChanged: (v) => onEdit((s) => s.copyWith(glass: v)),
          ),
        ]),
        SizedBox(height: t.space.md),
        Row(
          children: [
            Expanded(
              child: Text(
                dirty ? 'Unsaved changes' : 'Saved',
                style: t.text.captionStyle.copyWith(
                    color: dirty ? t.accent.active : t.surface.onBaseMuted),
              ),
            ),
            HcButton(
              label: saving ? 'Saving…' : 'Save',
              kind: HcButtonKind.primary,
              // Blocked only by the one finding that would leave the controls
              // themselves unreadable — see SkinReport.canSave.
              onPressed: (saving || !dirty || !canSave) ? null : onSave,
            ),
          ],
        ),
        if (!canSave)
          Padding(
            padding: EdgeInsets.only(top: t.space.xs),
            child: Text(
              'Body text is unreadable on its own background. Fix that and '
              'this saves.',
              style: t.text.captionStyle.copyWith(color: t.accent.danger),
            ),
          ),
        advanced,
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: t.space.xs),
            child: Text(label.toUpperCase(),
                style: t.text.overlineStyle
                    .copyWith(color: t.surface.onBaseMuted)),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// A colour, as a swatch and the hex someone can paste.
///
/// Not a colour wheel. A wheel is the right control for picking a light's hue
/// while looking at the light; a skin's palette is usually arrived at from a
/// value someone already has, and a hex field takes a paste.
class _ColourRow extends StatefulWidget {
  const _ColourRow(
      {required this.label, required this.value, required this.onChanged});

  final String label;
  final Color value;
  final ValueChanged<Color> onChanged;

  @override
  State<_ColourRow> createState() => _ColourRowState();
}

class _ColourRowState extends State<_ColourRow> {
  late final TextEditingController _c =
      TextEditingController(text: _hexOf(widget.value));
  bool _bad = false;

  static String _hexOf(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  void didUpdateWidget(covariant _ColourRow old) {
    super.didUpdateWidget(old);
    // Only when the value moved from elsewhere; rewriting it on every keystroke
    // would fight the cursor.
    if (old.value != widget.value && _hexOf(widget.value) != _c.text) {
      _c.text = _hexOf(widget.value);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.xs),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(widget.label,
                style: t.text.bodySmallStyle
                    .copyWith(color: t.surface.onBaseMuted)),
          ),
          // Wider than tall, on purpose. As a 22px square with a light border
          // and a near-black fill, the Ground swatch read as an unchecked
          // checkbox — the shape carried more meaning than the colour did.
          Container(
            width: 34,
            height: 20,
            decoration: BoxDecoration(
              color: widget.value,
              borderRadius: BorderRadius.circular(t.radius.xs),
              // Muted ink, not the hairline. A near-black ground on a
              // near-black page reads as an *empty* box against a hairline —
              // the swatch disappears in exactly the case it exists for, which
              // a screenshot showed and no test would have.
              border: Border.all(
                  color: t.surface.onBaseMuted, width: t.stroke.width),
            ),
          ),
          SizedBox(width: t.space.sm),
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
                    .resolve(t.text.bodySmall, mono: true)
                    .copyWith(color: t.surface.onBase),
                decoration: const InputDecoration(
                    isDense: true, border: InputBorder.none),
                onChanged: (raw) {
                  final parsed = parseSkinColour(raw.trim());
                  setState(() => _bad = parsed == null);
                  if (parsed != null) widget.onChanged(parsed);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.xs),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(label,
                style: t.text.bodySmallStyle
                    .copyWith(color: t.surface.onBaseMuted)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: t.accent.active,
                thumbColor: t.accent.active,
                inactiveTrackColor: t.accent.inactive,
                trackHeight: 3,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              format(value),
              textAlign: TextAlign.right,
              style: t.text
                  .resolve(t.text.caption, mono: true)
                  .copyWith(color: t.surface.onBase),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 92,
            child: Text(label,
                style: t.text.bodySmallStyle
                    .copyWith(color: t.surface.onBaseMuted)),
          ),
          Expanded(
            child: Wrap(
              spacing: t.space.xs,
              runSpacing: t.space.xs,
              children: [
                for (final entry in options.entries)
                  _Pick(
                    label: entry.value,
                    selected: entry.key == value,
                    onTap: () => onChanged(entry.key),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pick extends StatelessWidget {
  const _Pick(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: t.space.sm, vertical: t.space.xs / 2),
          decoration: BoxDecoration(
            color: selected ? t.surface.raised : null,
            borderRadius: BorderRadius.circular(t.radius.pill),
            border: Border.all(
              color: selected ? t.accent.active : t.stroke.hairline,
              width: t.stroke.width,
            ),
          ),
          child: Text(label,
              style: t.text.captionStyle.copyWith(
                  color: selected ? t.surface.onBase : t.surface.onBaseMuted)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The preview, and the report
// ---------------------------------------------------------------------------

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.tokens, required this.report});

  final HcTokens tokens;
  final SkinReport report;

  @override
  Widget build(BuildContext context) {
    final chrome = HcTokens.of(context);
    // Capped, not stretched. Given the whole pane the board grew to ~900px and
    // pushed the room's temperature reading eight hundred pixels away from the
    // room's name — a pairing that reads instantly at card width and not at all
    // at banner width. The findings share the cap so the pane is one column
    // rather than a card with a wider slab under it.
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('PREVIEW',
                style: chrome.text.overlineStyle
                    .copyWith(color: chrome.surface.onBaseMuted)),
            SizedBox(height: chrome.space.xs),
            // The nested Theme is the whole separation: inside it, every
            // HcTokens.of(context) answers with the skin being edited. Outside,
            // the chrome keeps the app's own.
            Theme(
              data: hcThemeFromTokens(tokens),
              child: Builder(builder: (context) => const _PreviewBoard()),
            ),
            SizedBox(height: chrome.space.lg),
            _Report(report: report),
          ],
        ),
      ),
    );
  }
}

/// Real components in real states.
///
/// Swatches would be easier and would lie: a palette that looks fine as
/// rectangles can still put unreadable text on a stale card. Every state that
/// has ever gone wrong in this app appears here — on, off, stale, offline,
/// fault, and a live number — so a skin is judged against the screens it will
/// actually have to survive.
class _PreviewBoard extends StatelessWidget {
  const _PreviewBoard();

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface.base,
        borderRadius: BorderRadius.circular(t.radius.md),
        border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
      ),
      padding: EdgeInsets.all(t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Kitchen',
                    style: t.text.titleStyle.copyWith(
                        color: t.surface.onBase, fontWeight: FontWeight.w700)),
              ),
              Text('21.4°',
                  style: t.text.titleStyle.copyWith(
                    color: t.metric.temperature,
                    fontFeatures: t.numericFontFeatures,
                  )),
            ],
          ),
          SizedBox(height: t.space.sm),
          Wrap(
            spacing: t.space.sm,
            runSpacing: t.space.sm,
            children: const [
              _Tile(label: 'Ceiling', state: _TileState.on),
              _Tile(label: 'Lamp', state: _TileState.off),
              _Tile(label: 'Sensor', state: _TileState.stale),
              _Tile(label: 'Garage', state: _TileState.offline),
              _Tile(label: 'Leak', state: _TileState.fault),
              _Tile(label: '1,284 W', state: _TileState.reading),
            ],
          ),
          _Rule(),
          // The type ramp, because `typeScale` is a control and a slider whose
          // effect you cannot see is a slider you cannot set. One line per role
          // rather than lorem: the sizes are the point, not the prose.
          // Spaced by the skin's own unit rather than set solid: at scale 1.0
          // the display and title lines all but touched, which reads as a
          // rendering fault and not as a ramp.
          for (final line in [
            (t.text.displayStyle, 'Every room, one glance', false),
            (t.text.titleStyle, 'Title — the name of a room', false),
            (
              t.text.bodyStyle,
              'Body — the sentence a card uses to explain '
                  'itself.',
              false
            ),
            (t.text.captionStyle, 'Caption — last seen 4 minutes ago', true),
          ])
            Padding(
              padding: EdgeInsets.only(bottom: t.space.xs),
              child: Text(line.$2,
                  style: line.$1.copyWith(
                      color:
                          line.$3 ? t.surface.onBaseMuted : t.surface.onBase)),
            ),
          _Rule(),
          // Buttons carry `onAccent`, which nothing else on the board does —
          // and a primary button with unreadable text is the most expensive
          // kind of unreadable there is.
          Wrap(
            spacing: t.space.sm,
            runSpacing: t.space.xs,
            children: [
              HcButton(
                  label: 'Run scene',
                  kind: HcButtonKind.primary,
                  onPressed: () {}),
              HcButton(label: 'Cancel', onPressed: () {}),
              HcButton(
                  label: 'Delete', kind: HcButtonKind.danger, onPressed: () {}),
              const HcButton(label: 'Unavailable', onPressed: null),
            ],
          ),
        ],
      ),
    );
  }
}

/// A hairline with the skin's own spacing around it.
class _Rule extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.md),
      child: Container(height: t.stroke.width, color: t.stroke.hairline),
    );
  }
}

enum _TileState { on, off, stale, offline, fault, reading }

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.state});

  final String label;
  final _TileState state;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final (fg, caption) = switch (state) {
      _TileState.on => (t.accent.active, 'On'),
      _TileState.off => (t.surface.onBaseMuted, 'Off'),
      _TileState.stale => (t.surface.onBaseMuted, 'Stale'),
      _TileState.offline => (t.accent.offline, 'Offline'),
      _TileState.fault => (t.accent.danger, 'Wet'),
      _TileState.reading => (t.metric.power, 'Now'),
    };

    return SizedBox(
      width: 132,
      child: HcSurface(
        padding: EdgeInsets.all(t.space.sm),
        glowColor: state == _TileState.on ? t.accent.active : null,
        glowIntensity: state == _TileState.on ? 1 : 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
                ),
                SizedBox(width: t.space.xs),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.text.bodySmallStyle
                          .copyWith(color: t.surface.onBase)),
                ),
              ],
            ),
            SizedBox(height: t.space.xs / 2),
            Text(caption, style: t.text.captionStyle.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

/// The live ratchet.
///
/// The same `validateSkin` CI runs against the shipped four, reporting while
/// the control is still under your hand rather than at save time.
class _Report extends StatelessWidget {
  const _Report({required this.report});

  final SkinReport report;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    if (report.isClean) {
      return Row(
        children: [
          Icon(HcIcons.check, size: 14, color: t.accent.success),
          SizedBox(width: t.space.xs),
          Text('Legible everywhere it was measured.',
              style: t.text.bodySmallStyle.copyWith(color: t.accent.success)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${report.findings.length} '
          '${report.findings.length == 1 ? 'problem' : 'problems'}',
          style: t.text.bodySmallStyle.copyWith(
              color: report.canSave ? t.accent.warn : t.accent.danger),
        ),
        SizedBox(height: t.space.xs),
        for (final f in report.findings)
          Container(
            margin: EdgeInsets.only(bottom: t.space.xs),
            padding: EdgeInsets.symmetric(
                horizontal: t.space.sm, vertical: t.space.xs),
            decoration: BoxDecoration(
              color: t.surface.raised,
              borderRadius: BorderRadius.circular(t.radius.sm),
              border: Border.all(
                color: f.blocking ? t.accent.danger : t.stroke.hairline,
                width: t.stroke.width,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.field,
                    style: t.text
                        .resolve(t.text.caption, mono: true)
                        .copyWith(color: t.surface.onBase)),
                Text(f.message,
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted, height: 1.4)),
              ],
            ),
          ),
      ],
    );
  }
}
