import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/code_runtime.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/tokens.dart';
import 'builtin_cards.dart';
import 'code_element.dart';

/// The card around a code element: who it may see, what it may do, and what
/// the skin looks like from inside it.
///
/// The sandbox is [CodeElement]'s job. This is the half that decides what goes
/// into it — and the decision is one sentence: **the element's device selection
/// is its permission.** The same `selectDevicesForConfig` every device card
/// uses resolves the grant, so "the living room lights" means exactly what it
/// means everywhere else in the app, and an element that names nothing is
/// handed nothing.
class CodeCard extends ConsumerStatefulWidget {
  const CodeCard({
    super.key,
    required this.config,
    this.editing = false,
    this.entered = false,
    this.onLog,
  });

  final Map<String, dynamic> config;

  /// The designer is drawing this card, so the frame must not take the pointer.
  final bool editing;

  /// …unless it has been entered, which is how you try a control you just
  /// wrote without leaving the designer to do it.
  final bool entered;

  final ValueChanged<String>? onLog;

  @override
  ConsumerState<CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends ConsumerState<CodeCard> {
  /// Proves a message came from this element's own frame. Made here rather
  /// than in [CodeElement] because the state message is built here and has to
  /// carry it.
  final String _nonce = codeNonce();

  /// The ids this element was granted, kept for the check on the way back.
  ///
  /// Recomputed on every build from the same selection the frame is fed, so a
  /// card whose room was changed under it cannot keep acting on the devices it
  /// used to have.
  var _granted = <String>{};

  void _set(String id, Map<String, dynamic> patch) {
    // The one rule that matters, checked outside the sandbox. A frame can ask
    // for anything; it gets what it was granted.
    if (!_granted.contains(id)) {
      widget.onLog?.call('Refused: this element was not given $id.');
      return;
    }
    ref.read(devicesProvider.notifier).command(id, patch);
  }

  /// The skin, as the author sees it.
  ///
  /// Named for what they are rather than for the token path — an author writes
  /// `var(--hc-accent)`, not `var(--hc-accent-active)` — and deliberately
  /// small. Every name here is a promise that has to keep working across
  /// skins, so a short list of the ones that mean something everywhere beats
  /// exporting the whole ramp.
  Map<String, String> _cssVars(HcTokens t) => {
        '--hc-base': _hex(t.surface.base),
        '--hc-raised': _hex(t.surface.raised),
        '--hc-sunken': _hex(t.surface.sunken),
        '--hc-ink': _hex(t.surface.onBase),
        '--hc-muted': _hex(t.surface.onBaseMuted),
        '--hc-accent': _hex(t.accent.active),
        '--hc-primary': _hex(t.accent.primary),
        '--hc-success': _hex(t.accent.success),
        '--hc-warn': _hex(t.accent.warn),
        '--hc-danger': _hex(t.accent.danger),
        '--hc-line': _hex(t.stroke.hairline),
        '--hc-radius': '${t.radius.md}px',
      };

  static String _hex(Color c) {
    int channel(double v) => (v * 255).round().clamp(0, 255);
    final r = channel(c.r).toRadixString(16).padLeft(2, '0');
    final g = channel(c.g).toRadixString(16).padLeft(2, '0');
    final b = channel(c.b).toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final all = ref.watch(devicesProvider).value ?? const <DeviceState>[];
    final granted = selectDevicesForConfig(all, widget.config);
    _granted = {for (final d in granted) d.id};

    final html = (widget.config['html'] as String?) ?? '';

    return CodeElement(
      html: html.isEmpty ? codeStarter : html,
      cssVars: _cssVars(t),
      nonce: _nonce,
      states: codeStateMessage(granted, _nonce),
      // Inert while it is being arranged, live when it is being used. Entering
      // the card is the way to try it without leaving the designer.
      live: !widget.editing || widget.entered,
      allowNetwork: widget.config['allow_network'] == true,
      // So a picture uploaded to this house resolves, while `default-src
      // 'none'` still refuses everywhere else.
      assetOrigin: Uri.base.origin,
      onSet: _set,
      onLog: widget.onLog,
    );
  }
}
