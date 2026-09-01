import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/card_style.dart';
import '../../core/dashboard/gauge_spec.dart';
import '../../core/dashboard/plugin_render.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/tokens.dart';
import 'gauge_card.dart';
import 'primitive_cards.dart';

/// Draws a plugin's card from its portable declaration.
///
/// The declaration names instruments, never markup, so this is a translation
/// and not an interpreter: each element kind maps onto a widget hc-web already
/// has — `GaugeDial`, `ShapePrimitiveCard`, `TextPrimitiveCard` — with the
/// portable field names translated into this app's own config keys.
///
/// **That translation layer is the point, not an inconvenience.** The portable
/// vocabulary says `outline` and `size_role`; hc-web's shape card says `shape`
/// and its text card says `size`. Handing a plugin this app's private config
/// keys would have made hc-web's idiom the contract, and every other client
/// would then be implementing hc-web rather than implementing homeCore.
class PluginRenderView extends ConsumerWidget {
  const PluginRenderView({
    super.key,
    required this.spec,
    required this.config,
  });

  final PluginWidgetSpec spec;

  /// The card's own config — what the person who placed it chose. Bindings
  /// resolve their device against this.
  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final render = spec.render;
    if (render == null) {
      // Core requires a render, so reaching here means this build could not
      // read the one that arrived — an older client against a newer core.
      return const _Unavailable(message: 'This build cannot read this card.');
    }

    final async = ref.watch(devicesProvider);
    if (async.value == null) return const _Unavailable(message: 'Loading…');

    final values = _resolveBindings(async.value!);
    return _draw(context, render, values);
  }

  /// Every binding's current reading, already mapped onto its instrument's
  /// range. A binding whose device is missing reads null rather than zero: a
  /// gauge at zero is a claim about the house, and "we do not know" is not it.
  Map<String, double?> _resolveBindings(List<DeviceState> devices) {
    final out = <String, double?>{};
    for (final binding in spec.bindings) {
      final id = binding.resolveDevice(config);
      if (id == null) {
        out[binding.name] = null;
        continue;
      }
      final device =
          devices.where((d) => d.id == id).cast<DeviceState?>().firstOrNull;
      final raw = device?.state[binding.key];
      out[binding.name] = binding.map(raw is num ? raw.toDouble() : null);
    }
    return out;
  }

  Widget _draw(
    BuildContext context,
    RenderNode node,
    Map<String, double?> values,
  ) =>
      switch (node.kind) {
        'gauge' => _gauge(context, node, values),
        'shape' => ShapePrimitiveCard(config: _shapeConfig(node)),
        'text' => TextPrimitiveCard(config: _textConfig(node, values)),
        'icon' => _icon(context, node),
        'row' || 'column' || 'stack' => _container(context, node, values),
        // A kind this build has never heard of. Core validated it against the
        // element vocabulary, so the card is not wrong — this app is behind,
        // and saying so is more use than an empty rectangle.
        _ => _Unavailable(message: 'Needs a newer app: ${node.kind}.'),
      };

  Widget _container(
    BuildContext context,
    RenderNode node,
    Map<String, double?> values,
  ) {
    final children = [
      for (final child in node.children) _draw(context, child, values),
    ];
    final gap = _number(node.fields['gap']) ?? 0;
    final align = node.fields['align'] as String?;

    return switch (node.kind) {
      'row' => Row(
          mainAxisAlignment: _mainAxis(align),
          children: _spaced(children, gap, horizontal: true),
        ),
      'column' => Column(
          mainAxisAlignment: _mainAxis(align),
          children: _spaced(children, gap, horizontal: false),
        ),
      // A stack has no gap to give — its children share the same box, which is
      // the whole reason to ask for one.
      _ => Stack(
          alignment: switch (align) {
            'start' => Alignment.topLeft,
            'end' => Alignment.bottomRight,
            _ => Alignment.center,
          },
          children: children,
        ),
    };
  }

  Widget _gauge(
    BuildContext context,
    RenderNode node,
    Map<String, double?> values,
  ) {
    final t = HcTokens.of(context);
    final value = values[node.fields['value'] as String? ?? ''];

    // 0–1 by default, which is the range a mapped binding already produces. A
    // declaration that feeds raw units says its own `max`, and one that mapped
    // them needs to say nothing — both read correctly without this having to
    // guess which idiom is in use.
    final min = _number(node.fields['min']) ?? 0;
    final max = _number(node.fields['max']) ?? 1;

    final spec = GaugeSpec.fromConfig(_gaugeConfig(node));
    return GaugeDial(
      spec: spec,
      fraction: GaugeSpec.fractionOf(value, min, max),
      fill: t.accent.active,
      text: value == null ? '—' : formatGaugeValue(value, spec.decimals),
    );
  }

  Widget _icon(BuildContext context, RenderNode node) {
    final t = HcTokens.of(context);
    return Icon(
      Icons.extension_outlined,
      color: resolveInk(t, node.fields['color'] as String?) ?? t.surface.onBase,
      semanticLabel: node.fields['name'] as String?,
    );
  }

  /// Portable gauge fields → this app's gauge config.
  ///
  /// `glow` is absent from the portable vocabulary on purpose — it is an SVG
  /// filter, and a field that renders here and vanishes on a client without one
  /// is worse than a field that does not exist — so nothing maps onto it and a
  /// portable gauge never glows.
  Map<String, dynamic> _gaugeConfig(RenderNode node) => {
        'shape': node.fields['shape'],
        'start': node.fields['start_degrees'],
        'sweep': node.fields['sweep_degrees'],
        'thickness': node.fields['thickness'],
        if (node.fields['round_cap'] == false) 'cap': 'flat',
        'track': node.fields['track'],
        'color': node.fields['color'],
        'color_to': node.fields['color_to'],
        'readout': node.fields['readout'],
        'decimals': node.fields['decimals'],
        'label': node.fields['label'],
      };

  Map<String, dynamic> _shapeConfig(RenderNode node) => {
        // The element's own `kind` key is taken by the node, so the portable
        // vocabulary calls a shape's outline `outline`.
        'shape': node.fields['outline'],
        'path': node.fields['path'],
        'fill': node.fields['color'],
        'corner': node.fields['corner']?.toString(),
      };

  /// Portable text fields → this app's text config.
  ///
  /// `content` names a binding when one answers to it, and is literal
  /// otherwise. That ordering is deliberate: a plugin that wants the words
  /// "flow" on a card whose binding is also called `flow` has a name collision
  /// it can rename its way out of, while a plugin that cannot show a number at
  /// all has nothing to do about it.
  Map<String, dynamic> _textConfig(
    RenderNode node,
    Map<String, double?> values,
  ) {
    final content = node.fields['content'] as String? ?? '';
    final decimals = _number(node.fields['decimals'])?.toInt();
    final unit = node.fields['unit'] as String? ?? '';

    final String text;
    if (spec.binding(content) != null) {
      final value = values[content];
      text = value == null
          ? '—'
          : '${formatGaugeValue(value, decimals)}${unit.isEmpty ? '' : ' $unit'}';
    } else {
      text = content;
    }

    return {
      'text': text,
      'size': node.fields['size_role'],
      'align': node.fields['align'],
      'ink': node.fields['color'],
    };
  }

  static List<Widget> _spaced(
    List<Widget> children,
    double gap, {
    required bool horizontal,
  }) {
    if (gap <= 0 || children.length < 2) return children;
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        out.add(horizontal ? SizedBox(width: gap) : SizedBox(height: gap));
      }
      out.add(children[i]);
    }
    return out;
  }

  static MainAxisAlignment _mainAxis(String? align) => switch (align) {
        'center' => MainAxisAlignment.center,
        'end' => MainAxisAlignment.end,
        _ => MainAxisAlignment.start,
      };

  static double? _number(Object? raw) =>
      raw is num && raw.toDouble().isFinite ? raw.toDouble() : null;
}

/// Said rather than drawn blank.
///
/// A card that cannot be drawn and a card that is empty look identical as an
/// empty rectangle, and only one of them is somebody's problem to fix.
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: t.surface.onBaseMuted),
      ),
    );
  }
}
