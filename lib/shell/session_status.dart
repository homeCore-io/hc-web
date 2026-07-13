import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/providers/auth_provider.dart';
import '../core/providers/events_provider.dart';
import '../design/tokens.dart';

/// Minutes until the access token expires, refreshed once a minute.
///
/// A wall panel runs unattended for weeks, so a token quietly expiring behind a
/// dashboard is a real failure mode — the screen keeps showing the last state it
/// saw and looks perfectly healthy while being completely stale.
final tokenExpiryProvider = StreamProvider<Duration?>((ref) async* {
  Future<Duration?> remaining() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) return null;

    final parts = token.split('.');
    if (parts.length != 3) return null;

    var payload = parts[1];
    payload += switch (payload.length % 4) {
      2 => '==',
      3 => '=',
      _ => '',
    };

    try {
      final json = jsonDecode(utf8.decode(base64Url.decode(payload)))
          as Map<String, dynamic>;
      final exp = json['exp'] as int?;
      if (exp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000)
          .difference(DateTime.now());
    } catch (_) {
      return null;
    }
  }

  yield await remaining();
  await for (final _ in Stream.periodic(const Duration(minutes: 1))) {
    yield await remaining();
  }
});

/// The live-connection dot.
///
/// On a wall panel this is the single most important pixel on the screen: it is
/// the difference between "the house is quiet" and "this display has been lying
/// to you for an hour".
class LiveDot extends ConsumerWidget {
  const LiveDot({super.key, this.size = 10, this.showLabel = false});

  final double size;
  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final connected = ref.watch(wsConnectedProvider).valueOrNull ?? true;

    final dot = AnimatedContainer(
      duration: t.motion.d(t.motion.base),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: connected ? t.accent.success : t.accent.danger,
        boxShadow: [
          if (connected && t.glow.enabled)
            BoxShadow(
              color: t.accent.success.withValues(alpha: 0.6),
              blurRadius: size,
            ),
        ],
      ),
    );

    if (!showLabel) {
      return Tooltip(
        message:
            connected ? 'Live — connected' : 'Disconnected — reconnecting…',
        child: dot,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        SizedBox(width: t.space.sm),
        Text(
          connected ? 'Live' : 'Reconnecting…',
          style: TextStyle(
            color: connected ? t.surface.onBaseMuted : t.accent.danger,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// Warns before the session dies, rather than after.
class ExpiryBanner extends ConsumerWidget {
  const ExpiryBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final remaining = ref.watch(tokenExpiryProvider).valueOrNull;

    if (remaining == null || remaining.inMinutes >= 60) {
      return const SizedBox.shrink();
    }

    final expired = remaining.isNegative;

    return Material(
      color: t.accent.danger.withValues(alpha: 0.16),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: t.space.md,
          vertical: t.space.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_outlined,
                size: 16, color: t.accent.danger),
            SizedBox(width: t.space.sm),
            Expanded(
              child: Text(
                expired
                    ? 'Session expired.'
                    : 'Session expires in ${remaining.inMinutes} min.',
                style: TextStyle(fontSize: 13, color: t.accent.danger),
              ),
            ),
            TextButton(
              onPressed: () => ref.read(authProvider.notifier).logout(),
              child: const Text('Sign in again'),
            ),
          ],
        ),
      ),
    );
  }
}
