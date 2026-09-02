import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/card_style.dart';
import '../../core/devices/scene_state.dart';
import '../../core/models/device_state.dart';
import '../../core/models/scene.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/scenes_provider.dart';
import '../../design/tokens.dart';

/// A button for one scene, drawn where you want it.
///
/// **Scenes activate directly, like a device.** No rule stands between the
/// button and the house, so this carries none of the switch's writability
/// machinery — a scene either exists or it does not.
///
/// **There are two kinds and they are not interchangeable.** A native scene
/// lives at `/scenes` and is applied with a POST; a plugin scene arrives as a
/// *device* with `device_type == 'scene'` and is applied by setting
/// `activate`. Getting this wrong is not a small bug — the request goes to the
/// wrong endpoint and nothing happens.
///
/// **Only one of them can say whether it is on.** A bridge knows: Hue publishes
/// `active`, Lutron publishes `on` from the phantom-button LED. Core does not
/// track whether a native scene is still in effect, because the devices moved
/// and nothing recorded why. So this shows a state for the scenes that report
/// one and says nothing for the rest — reporting every native scene as "off"
/// would be inventing a fact.
class SceneButtonElement extends ConsumerStatefulWidget {
  const SceneButtonElement({super.key, required this.config});

  final Map<String, dynamic> config;

  @override
  ConsumerState<SceneButtonElement> createState() => _SceneButtonElementState();
}

enum _Said { nothing, sending, failed }

class _SceneButtonElementState extends ConsumerState<SceneButtonElement> {
  _Said _said = _Said.nothing;
  Timer? _clear;

  @override
  void dispose() {
    _clear?.cancel();
    super.dispose();
  }

  /// Applies the scene the way its own kind is applied.
  Future<void> _activate({required String id, required bool isPlugin}) async {
    _clear?.cancel();
    setState(() => _said = _Said.sending);
    try {
      if (isPlugin) {
        await ref.read(devicesApiProvider).setDeviceState(id, {
          'activate': true,
        });
      } else {
        await ref.read(scenesApiProvider).activateScene(id);
      }
      // Success is not announced. A scene that reports its state will show it,
      // and one that does not has nothing true to say — a tick that meant only
      // "the request returned 200" would be the button congratulating itself.
      if (mounted) setState(() => _said = _Said.nothing);
    } catch (_) {
      if (mounted) setState(() => _said = _Said.failed);
      _clear = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _said = _Said.nothing);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final config = widget.config;
    final id = (config['scene_id'] as String? ?? '').trim();

    final native = ref.watch(scenesProvider).value;
    final devices = ref.watch(devicesProvider).value;

    final nativeScene = native == null || id.isEmpty
        ? null
        : native.where((s) => s.id == id).cast<SceneModel?>().firstOrNull;
    final pluginScene = devices == null || id.isEmpty
        ? null
        : devices
            .where((d) => d.id == id && isSceneDevice(d))
            .cast<DeviceState?>()
            .firstOrNull;

    final isPlugin = pluginScene != null;
    // A scene deleted after the page was made. The button stays where somebody
    // put it and stops pretending it does anything.
    final live = nativeScene != null || isPlugin;

    final knowsState = sceneStateIsKnowable(isPlugin: isPlugin);
    final on = isPlugin && sceneActive(pluginScene.state);

    final name = pluginScene?.displayName ?? nativeScene?.name;
    final label = (config['label'] as String? ?? '').trim();
    final ink = resolveInk(t, config['ink'] as String?) ?? t.accent.active;

    final failed = _said == _Said.failed;
    final tint = failed
        ? t.accent.danger
        : (knowsState && on)
            ? ink
            : t.surface.onBaseMuted;

    return Semantics(
      button: true,
      enabled: live,
      // Only claimed where it is known. `toggled` on a native scene would be
      // announcing a state nobody tracks.
      toggled: knowsState ? on : null,
      label: label.isEmpty ? name ?? 'Scene' : label,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: live ? 1 : .4,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: live && _said != _Said.sending
                ? () => _activate(id: id, isPlugin: isPlugin)
                : null,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: t.space.md,
                vertical: t.space.sm,
              ),
              decoration: BoxDecoration(
                color: (knowsState && on)
                    ? ink.withValues(alpha: .16)
                    : t.surface.raised,
                border: Border.all(
                  color: failed
                      ? t.accent.danger
                      : (knowsState && on)
                          ? ink.withValues(alpha: .5)
                          : t.stroke.hairline,
                ),
                borderRadius: t.radius.smR,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    switch (_said) {
                      _Said.sending => Icons.more_horiz,
                      _Said.failed => Icons.close,
                      _Said.nothing => Icons.play_arrow_rounded,
                    },
                    size: 16,
                    color: tint,
                  ),
                  SizedBox(width: t.space.xs),
                  Flexible(
                    child: Text(
                      label.isEmpty ? name ?? 'Pick a scene' : label,
                      overflow: TextOverflow.ellipsis,
                      style: t.text.bodyStyle.copyWith(color: t.surface.onBase),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
