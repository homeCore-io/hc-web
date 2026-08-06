import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/command_failure_provider.dart';
import '../design/tokens.dart';

/// Says so when the house did not take an instruction.
///
/// Modelled on the wall shell's "Not live — showing last known state", which
/// already makes the same argument for the socket: a state you cannot see is a
/// state you do not have. This is the write half of it.
///
/// A banner rather than a snackbar, deliberately. A snackbar is the wrong shape
/// for an unattended panel — it lasts four seconds and assumes someone is
/// watching, and the wall is a screen nobody is looking at most of the time.
/// Whoever walks up two minutes later still needs to know their light never
/// switched. It stays until dismissed, or until a later command lands.
class CommandFailureBanner extends ConsumerWidget {
  const CommandFailureBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failure = ref.watch(commandFailureProvider);
    if (failure == null) return const SizedBox.shrink();

    final t = HcTokens.of(context);
    return Material(
      color: t.accent.danger.withValues(alpha: 0.16),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: t.space.md,
          vertical: t.space.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 16, color: t.accent.danger),
            SizedBox(width: t.space.sm),
            Expanded(
              // The device by name, because "a command failed" is not something
              // anyone can act on. The one that did not move is the point.
              child: Text(
                '${failure.deviceName} did not respond — it has been put back '
                'to how it was.',
                style: t.text.bodyStyle.copyWith(color: t.surface.onBase),
              ),
            ),
            SizedBox(width: t.space.sm),
            TextButton(
              onPressed: () =>
                  ref.read(commandFailureProvider.notifier).clear(),
              child: Text('Dismiss',
                  style: t.text.bodyStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: t.accent.danger,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
