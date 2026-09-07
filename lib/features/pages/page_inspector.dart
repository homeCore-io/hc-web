import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dashboard/grid_engine.dart';
import '../../core/dashboard/room_scope.dart';
import '../../core/devices/breakdown.dart' show prettyGroup;
import '../../core/models/dashboard.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/page_room_provider.dart';
import '../../design/tokens.dart';
import '../assets/asset_field.dart';
import 'inspector_controls.dart';
import 'inspector_fields.dart';

/// The page itself, when no card is selected.
///
/// The right pane used to say "Select a card to change what it shows." and
/// nothing else, which meant a 340px column sat blank for most of a session —
/// a panel that is dead by default teaches you to stop looking at it.
///
/// A design tool's inspector always has a subject: the selection, or the
/// document. This is the document.
///
/// **It is also where the flow control lives**, and that matters more than it
/// looks. Whether gaps are kept was until now settable only as a side effect of
/// dragging a card, and readable only in the status bar. A property of the page
/// that you can trip over but not set is a property nobody controls.
class PageInspector extends StatefulWidget {
  const PageInspector({
    super.key,
    required this.dashboard,
    required this.breakpoint,
    required this.layout,
    required this.cardCount,
    required this.onFlowChanged,
    required this.onComposeChanged,
    required this.onFrameChanged,
    required this.snapToGrid,
    required this.onSnapChanged,
    this.sourceComposed = false,
    this.onBackgroundChanged,
  });

  final DashboardDefinition dashboard;
  final DashboardBreakpoint breakpoint;
  final DashboardLayout? layout;

  /// Whether the layout this one follows is itself a composition.
  ///
  /// Passed in rather than read off [dashboard], because the answer has to
  /// come from the *draft*: turning composition on for the desktop and then
  /// looking at the phone must say so before anything is saved.
  final bool sourceComposed;
  final int cardCount;
  final ValueChanged<GridFlow>? onFlowChanged;

  /// Turn composition on, or hand the layout back to the grid.
  final ValueChanged<bool>? onComposeChanged;

  /// Resize the canvas, or change what its height promises.
  final ValueChanged<DashboardFrame>? onFrameChanged;

  /// Whether a composed drag is pulled to the cell edges. View state — how you
  /// are working on a page, not a fact about the page.
  final bool snapToGrid;
  final ValueChanged<bool>? onSnapChanged;

  /// Null outside the designer — the page inspector also renders where there is
  /// nothing to save into.
  final ValueChanged<DashboardBackground>? onBackgroundChanged;

  @override
  State<PageInspector> createState() => _PageInspectorState();
}

class _PageInspectorState extends State<PageInspector> {
  /// See [CardInspector]: an unmanaged scroll view draws no scrollbar on web,
  /// so a pane with more in it than fits says nothing about the fact.
  final _scroll = ScrollController();

  /// Whether anything on this page is written about *the room it is opened
  /// for* rather than about a named one.
  ///
  /// Only then is there a room to pick: offering the control on every page
  /// would be offering a setting that does nothing on all but one of them.
  bool get _saysRoom => widget.dashboard.widgets.any(
        (w) => mentionsRoom(w.config),
      );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = widget.dashboard;
    final layout = widget.layout;
    final breakpoint = widget.breakpoint;
    final onFlowChanged = widget.onFlowChanged;
    final onBackgroundChanged = widget.onBackgroundChanged;
    final t = HcTokens.of(context);
    final flow = layout?.flow ?? GridFlow.packed;
    final derived = layout?.derivedFrom;
    // Whether the layout this one follows is itself a composition. Following
    // an ordinary layout loses nothing; following a composed one loses the
    // free positions, and that is worth saying out loud.
    final sourceComposed = derived != null && widget.sourceComposed;
    final composed = layout?.isComposed ?? false;

    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scroll,
        padding:
            EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The subject, the way a title bar names a document: what it is,
            // and what is true of it, without a sentence about either.
            Padding(
              padding: EdgeInsets.only(bottom: t.space.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(dashboard.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.text.bodyStyle.copyWith(
                            color: t.surface.onBase,
                            fontWeight: FontWeight.w600)),
                  ),
                  Text('This page',
                      style: t.text.captionStyle
                          .copyWith(color: t.surface.onBaseMuted)),
                ],
              ),
            ),
            InspectorSection(title: 'Page', children: [
              InspectorField(
                label: 'Cards',
                child: _Reading('${widget.cardCount}'),
              ),
              InspectorField(
                label: 'Columns',
                child: _Reading('${layout?.columns ?? 12}'),
              ),
              InspectorField(
                label: 'Arranging',
                child: _Reading(_breakpointName(breakpoint)),
              ),
            ]),

            // **A page about a room has to be designable as one.** Everything
            // on it that says `@room` resolves against the room it was opened
            // for, and without one the canvas is a set of empty boxes reading
            // "No devices match".
            if (_saysRoom)
              InspectorSection(title: 'Preview', children: [
                InspectorField(
                  label: 'Room',
                  help: 'Which room to arrange this page against.',
                  child: _RoomPreviewPicker(dashboardId: widget.dashboard.id),
                ),
              ]),

            InspectorSection(title: 'Layout', children: [
              if (derived != null)
                InspectorField(
                  label: 'Space',
                  help: 'Follows another layout, so it is packed for its own '
                      'width. Arrange it by hand to give it gaps of its own.',
                  child: _Reading('Follows ${_breakpointName(derived)}'),
                )
              else
                InspectorField(
                  label: 'Space',
                  child: InspectorSegments(
                    options: const ['packed', 'free'],
                    value: flow == GridFlow.free ? 'free' : 'packed',
                    labelFor: (o) => o == 'free' ? 'Keep gaps' : 'Close gaps',
                    onChanged: onFlowChanged == null
                        ? (_) {}
                        : (o) => onFlowChanged(
                            o == 'free' ? GridFlow.free : GridFlow.packed),
                  ),
                ),
              if (widget.onComposeChanged case final onCompose?) ...[
                InspectorField(
                  label: 'Compose',
                  // The one case where following costs something visible, and
                  // the only sentence in this section that earns its line.
                  help: sourceComposed
                      ? 'This follows a composed layout, so that composition '
                          'is packed into these cells.'
                      : null,
                  child: InspectorSwitch(
                    value: composed,
                    semanticLabel: 'Compose freely',
                    onChanged: derived != null ? (_) {} : (v) => onCompose(v),
                  ),
                ),
                if (layout?.frame != null)
                  InspectorField(
                    label: 'Snap',
                    child: InspectorSwitch(
                      value: widget.snapToGrid,
                      semanticLabel: 'Snap to the grid',
                      onChanged: widget.onSnapChanged ?? (_) {},
                    ),
                  ),
              ],
            ]),

            if (widget.onComposeChanged != null && layout?.frame != null)
              _FrameControls(
                frame: layout!.frame!,
                onChanged: widget.onFrameChanged,
              ),

            if (onBackgroundChanged != null)
              InspectorSection(title: 'Background', children: [
                _BackgroundControls(
                  value: dashboard.background ?? const DashboardBackground(),
                  onChanged: onBackgroundChanged,
                ),
              ]),
            SizedBox(height: t.space.md),
          ],
        ),
      ),
    );
  }

  static String _breakpointName(DashboardBreakpoint b) => switch (b) {
        DashboardBreakpoint.mobile => 'Mobile',
        DashboardBreakpoint.tablet => 'Tablet',
        DashboardBreakpoint.desktop => 'Desktop',
        DashboardBreakpoint.tv => 'Wall',
      };
}

/// A value the panel states rather than asks for.
///
/// The same line height and the same column as every editable value, because a
/// panel where the facts and the settings sit at different heights reads as two
/// panels stacked.
class _Reading extends StatelessWidget {
  const _Reading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text,
          style: t.text.bodySmallStyle.copyWith(
              color: t.surface.onBaseMuted,
              fontFeatures: t.numericFontFeatures)),
    );
  }
}

/// Image, blur and dim — with the two sliders present from the start.
///
/// They are not "advanced". A photograph behind live content is unreadable
/// without them, so hiding them behind a disclosure would mean the first thing
/// anyone sees after pasting a URL is a page they cannot read, and the fix one
/// click away and invisible.
class _BackgroundControls extends StatefulWidget {
  const _BackgroundControls({required this.value, required this.onChanged});

  final DashboardBackground value;
  final ValueChanged<DashboardBackground> onChanged;

  @override
  State<_BackgroundControls> createState() => _BackgroundControlsState();
}

class _BackgroundControlsState extends State<_BackgroundControls> {
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final v = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AssetField(
          value: v.image ?? '',
          onChanged: (s) =>
              widget.onChanged(v.copyWith(image: s.isEmpty ? null : s)),
        ),
        SizedBox(height: t.space.xs),
        InspectorSlider(
          label: 'Blur',
          value: v.blur,
          max: 40,
          onChanged: (n) => widget.onChanged(v.copyWith(blur: n)),
        ),
        InspectorSlider(
          label: 'Dim',
          value: v.dim * 100,
          max: 100,
          onChanged: (n) => widget.onChanged(v.copyWith(dim: n / 100)),
        ),
        Text(
          v.isEmpty
              ? 'A picture behind the whole page. Blur and dim are what keep '
                  'the cards readable on top of it.'
              : 'Blurred and dimmed behind the cards; the cards stay sharp.',
          style: t.text.captionStyle
              .copyWith(color: t.surface.onBaseMuted, height: 1.4),
        ),
      ],
    );
  }
}

/// A labelled switch, using the house control rather than Material's.
///
/// `SwitchListTile` paints its background on the nearest `Material` ancestor,
/// and this pane is a `DecoratedBox` — which Flutter asserts about, loudly,
/// in every test that opens the designer.
/// The canvas's own size, and what its height promises.
///
/// **Presets first, then the numbers.** A wall layout is almost always a
/// display somebody owns, and the useful question is *which screen* — not what
/// 3840 divided by anything is. The fields are there for the case a preset does
/// not cover, which is real but rare.
class _FrameControls extends StatefulWidget {
  const _FrameControls({required this.frame, required this.onChanged});

  final DashboardFrame frame;
  final ValueChanged<DashboardFrame>? onChanged;

  @override
  State<_FrameControls> createState() => _FrameControlsState();
}

/// The canvas sizes worth one click.
///
/// Screens people actually design walls and tablets for, and nothing else — a
/// list of every resolution would be a menu you have to read rather than one
/// you can point at.
const _presets = <String, (double, double)>{
  '720p': (1280, 720),
  '1080p': (1920, 1080),
  '1440p': (2560, 1440),
  '4K': (3840, 2160),
};

class _FrameControlsState extends State<_FrameControls> {
  @override
  Widget build(BuildContext context) {
    final onChanged = widget.onChanged;
    final size =
        '${widget.frame.width.round()} × ${widget.frame.height.round()}';
    final preset = _presets.entries
        .where((e) =>
            widget.frame.width == e.value.$1 &&
            widget.frame.height == e.value.$2)
        .map((e) => e.key)
        .firstOrNull;

    return InspectorSection(title: 'Canvas', children: [
      InspectorField(
        label: 'Width',
        child: InspectorNumber(
          value: widget.frame.width,
          unit: 'px',
          // **A canvas with no width divides by zero on the way to the
          // screen**, and core rejects it — so a 0, or a word, leaves the
          // canvas as it was rather than becoming one.
          onChanged: (n) => onChanged == null || n == null || n <= 0
              ? null
              : onChanged(widget.frame.copyWith(width: n.toDouble())),
        ),
      ),
      InspectorField(
        label: 'Height',
        child: InspectorNumber(
          value: widget.frame.height,
          unit: 'px',
          onChanged: (n) => onChanged == null || n == null || n <= 0
              ? null
              : onChanged(widget.frame.copyWith(height: n.toDouble())),
        ),
      ),
      // **The presets are a menu, not five pills.** Four names and a "custom"
      // that is whatever the numbers above say: a row of segments would be
      // five words in two hundred pixels, and the numbers are already there
      // for anyone who wants an exact one.
      InspectorField(
        label: 'Preset',
        child: InspectorMenu(
          options: _presets.keys.toList(),
          value: preset,
          hint: size,
          onChanged: (name) {
            final chosen = _presets[name];
            if (chosen == null || onChanged == null) return;
            onChanged(
                widget.frame.copyWith(width: chosen.$1, height: chosen.$2));
          },
        ),
      ),
      InspectorField(
        label: 'Height is',
        // The one thing here that is not obvious from the value: what a fixed
        // canvas *does* on a screen that is not its size.
        help: switch (widget.frame.fit) {
          DashboardFrameFit.scroll =>
            'A starting point. The page carries on below it and scrolls.',
          DashboardFrameFit.fixed =>
            'The whole canvas at once, scaled to fit. What a wall display is.',
        },
        child: InspectorSegments(
          options: const ['scroll', 'fixed'],
          value:
              widget.frame.fit == DashboardFrameFit.fixed ? 'fixed' : 'scroll',
          labelFor: (o) => o == 'fixed' ? 'Fixed' : 'Grows',
          onChanged: (o) => onChanged?.call(widget.frame.copyWith(
              fit: o == 'fixed'
                  ? DashboardFrameFit.fixed
                  : DashboardFrameFit.scroll)),
        ),
      ),
    ]);
  }
}

/// Which room the designer draws this page as.
///
/// A navigation rather than a setting: the room lives in the page's address,
/// the same `?room=` a room card sends, so the canvas you arrange is the page
/// somebody will actually open — and the link is shareable.
class _RoomPreviewPicker extends ConsumerWidget {
  const _RoomPreviewPicker({required this.dashboardId});

  final String dashboardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final rooms = {
      for (final d in ref.watch(devicesProvider).value ?? const <DeviceState>[])
        if ((d.effectiveArea ?? '').isNotEmpty) d.effectiveArea!,
    }.toList()
      ..sort();
    final current = ref.watch(pageRoomProvider);

    if (rooms.isEmpty) {
      return Text('No rooms yet.',
          style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted));
    }

    return DropdownButtonFormField<String>(
      initialValue: rooms.contains(current) ? current : null,
      isExpanded: true,
      decoration:
          const InputDecoration(isDense: true, border: OutlineInputBorder()),
      hint: const Text('No room'),
      items: [
        for (final r in rooms)
          DropdownMenuItem(value: r, child: Text(prettyGroup(r))),
      ],
      onChanged: (v) {
        if (v == null) return;
        context.go('/pages/$dashboardId/design?room=$v');
      },
    );
  }
}
