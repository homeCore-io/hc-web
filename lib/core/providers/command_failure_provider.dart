import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A command core never accepted.
///
/// Commands are applied optimistically — the tile has to move the instant you
/// touch it, or a light switch feels broken. The bet behind that is written in
/// `DevicesNotifier.command`: *"If core rejects it, the next WS frame corrects
/// us."*
///
/// That bet is good for a rejection and worthless for a failure to deliver,
/// because the two cases that break the send are the same two that stop the
/// frame arriving: core is down, or the network is. So the one moment the
/// optimistic state most needs correcting is the one moment nothing is coming
/// to correct it. The tile keeps saying the light is on. It says so until
/// someone reloads the page.
///
/// A failed write also had nowhere to be seen. There is no `FlutterError.onError`
/// or zone guard in this app, and all 41 call sites are fire-and-forget
/// (`onPressed: () => notifier.command(...)`), so the exception went to the
/// client error log — Administration › Logs › Client Errors, several navigations
/// away from the switch you just pressed and did not watch fail.
class CommandFailure {
  const CommandFailure({
    required this.deviceId,
    required this.deviceName,
    required this.error,
    required this.at,
  });

  final String deviceId;
  final String deviceName;
  final Object error;
  final DateTime at;
}

class CommandFailureNotifier extends Notifier<CommandFailure?> {
  @override
  CommandFailure? build() => null;

  void report(CommandFailure f) => state = f;

  /// Called when a later command lands, so one recovered failure does not leave
  /// a banner up over a house that is now answering perfectly well.
  void clear() => state = null;
}

final commandFailureProvider =
    NotifierProvider<CommandFailureNotifier, CommandFailure?>(
  CommandFailureNotifier.new,
);
