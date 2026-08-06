import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/events_provider.dart';
import '../design/tokens.dart';
import 'session_status.dart';

/// True while the UI is running as a wall panel.
///
/// Pages read this to suppress anything destructive: nobody wants a guest to
/// lean on the panel and delete a rule. It is a *presentation* guard, not a
/// security control — core's roles are the real boundary.
class KioskNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// One-way: the wall panel sets this when it mounts and nothing clears it.
  /// Navigating off /wall within the same session deliberately leaves the
  /// guard on rather than briefly re-arming the destructive actions.
  void enter() => state = true;
}

final kioskProvider = NotifierProvider<KioskNotifier, bool>(KioskNotifier.new);

/// How long without a touch before the panel dims, then sleeps.
const _dimAfter = Duration(minutes: 2);
const _sleepAfter = Duration(minutes: 5);

/// A screen bolted to a wall, read from across a room, usually in the dark, and
/// left running for weeks.
///
/// That last part drives most of what is unusual here:
///
/// * **No navigation chrome.** A wall panel is not browsed; it shows one thing.
/// * **It dims, then sleeps.** A dashboard at full brightness in a dark room at
///   3am is a lamp, not a display.
/// * **Burn-in drift.** OLED panels retain static pixels. The whole surface
///   creeps a few pixels on a slow cycle, which is invisible to a person and
///   sufficient to save the panel.
/// * **It admits when it is stale.** An unattended screen that has quietly lost
///   its connection is worse than a blank one, because it looks fine.
class WallChrome extends ConsumerStatefulWidget {
  const WallChrome({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WallChrome> createState() => _WallChromeState();
}

class _WallChromeState extends ConsumerState<WallChrome> {
  Timer? _idle;
  Timer? _clock;
  Timer? _drift;

  DateTime _now = DateTime.now();
  bool _dimmed = false;
  bool _asleep = false;

  /// Slow positional offset, cycled to keep static pixels moving.
  Offset _shift = Offset.zero;
  int _driftStep = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(kioskProvider.notifier).enter();
    });

    _wake();
    _clock = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    // Six positions around a small circle, one step every quarter hour: about
    // ±6px of travel, which no one will notice and the panel will thank us for.
    _drift = Timer.periodic(const Duration(minutes: 15), (_) {
      if (!mounted) return;
      setState(() {
        _driftStep++;
        final angle = (_driftStep % 6) * (math.pi / 3);
        _shift = Offset(math.cos(angle) * 6, math.sin(angle) * 6);
      });
    });
  }

  void _wake() {
    _idle?.cancel();
    if (_dimmed || _asleep) {
      setState(() {
        _dimmed = false;
        _asleep = false;
      });
    }
    _idle = Timer(_dimAfter, () {
      if (!mounted) return;
      setState(() => _dimmed = true);
      _idle = Timer(_sleepAfter - _dimAfter, () {
        if (!mounted) return;
        setState(() => _asleep = true);
        // Whatever the last person navigated to, come back to the default view —
        // the panel should always be found showing the thing it is for.
        if (GoRouterState.of(context).matchedLocation != '/wall') {
          context.go('/wall');
        }
      });
    });
  }

  @override
  void dispose() {
    _idle?.cancel();
    _clock?.cancel();
    _drift?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Scaffold(
      backgroundColor: t.surface.base,
      body: Listener(
        // Any contact at all wakes it — including the touch that will also be
        // delivered to whatever is underneath, so waking never costs a tap.
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _wake(),
        onPointerHover: (_) => _wake(),
        child: Stack(
          children: [
            AnimatedOpacity(
              opacity: _asleep ? 0.0 : (_dimmed ? 0.45 : 1.0),
              duration: t.motion.d(t.motion.slow),
              child: AnimatedSlide(
                offset: Offset(_shift.dx / 100, _shift.dy / 100),
                duration: const Duration(seconds: 4),
                curve: Curves.easeInOut,
                child: Column(
                  children: [
                    _statusBar(context, t),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ),
            if (_asleep) _screensaver(context, t),
          ],
        ),
      ),
    );
  }

  /// One line: the time, and whether anything on this screen can be believed.
  Widget _statusBar(BuildContext context, HcTokens t) {
    final connected = ref.watch(wsConnectedProvider).value ?? true;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        t.space.lg,
        t.space.md,
        t.space.lg,
        t.space.sm,
      ),
      child: Row(
        children: [
          Text(
            _hhmm(_now),
            style: TextStyle(
                fontSize: t.text.scaled(34),
                fontWeight: FontWeight.w200,
                height: 1,
                color: t.surface.onBase,
                fontFeatures: t.numericFontFeatures),
          ),
          SizedBox(width: t.space.md),
          Text(
            _dayLabel(_now),
            style: t.text.subtitleStyle.copyWith(color: t.surface.onBaseMuted),
          ),
          const Spacer(),

          // A stale wall panel looks exactly like a healthy one. When the socket
          // drops, say so in words — a 10px dot is not enough from three metres.
          if (!connected)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: t.space.md,
                vertical: t.space.xs,
              ),
              decoration: BoxDecoration(
                color: t.accent.danger.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(t.radius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off, size: 16, color: t.accent.danger),
                  SizedBox(width: t.space.sm),
                  Text(
                    'Not live — showing last known state',
                    style: t.text.bodyStyle.copyWith(color: t.accent.danger),
                  ),
                ],
              ),
            )
          else
            const LiveDot(size: 8),
        ],
      ),
    );
  }

  /// Asleep: a clock, and nothing else. Still touch-reactive, so the panel wakes
  /// the instant someone walks up to it.
  Widget _screensaver(BuildContext context, HcTokens t) => Positioned.fill(
        child: AnimatedSlide(
          offset: Offset(_shift.dx / 60, _shift.dy / 60),
          duration: const Duration(seconds: 4),
          curve: Curves.easeInOut,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _hhmm(_now),
                  style: TextStyle(
                      fontSize: t.text.scaled(96),
                      fontWeight: FontWeight.w100,
                      height: 1,
                      color: t.surface.onBaseMuted.withValues(alpha: 0.55),
                      fontFeatures: t.numericFontFeatures),
                ),
                SizedBox(height: t.space.sm),
                Text(
                  _dayLabel(_now),
                  style: t.text.titleStyle.copyWith(
                      color: t.surface.onBaseMuted.withValues(alpha: 0.4)),
                ),
              ],
            ),
          ),
        ),
      );

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _dayLabel(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }
}
