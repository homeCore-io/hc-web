import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/automations_provider.dart';
import '../core/providers/devices_provider.dart';
import '../design/tokens.dart';
import 'shell_scope.dart';

/// One thing you can jump to or do.
class Command {
  const Command({
    required this.label,
    required this.category,
    required this.onRun,
    this.subtitle,
    this.icon,
  });

  final String label;
  final String category;
  final String? subtitle;
  final IconData? icon;
  final void Function(BuildContext) onRun;
}

/// Everything reachable by name: the nav destinations, every device, every rule.
///
/// The admin portal's whole premise is that you already know what you want. With
/// 168 devices and 42 rules, typing three letters beats navigating to a list and
/// filtering it, every time.
List<Command> buildCommands(WidgetRef ref) {
  final devices = ref.watch(devicesProvider).value ?? const [];
  final rules = ref.watch(automationsProvider).value ?? const [];

  return [
    for (final i in kPlaces)
      Command(
        label: i.label,
        category: 'Go to',
        icon: i.icon,
        onRun: (context) => context.go(i.route),
      ),
    for (final d in devices)
      Command(
        label: d.displayName,
        category: 'Devices',
        subtitle: d.effectiveArea ?? d.pluginId,
        icon: Icons.devices_outlined,
        onRun: (context) => context.go('/devices/${d.id}'),
      ),
    for (final r in rules)
      Command(
        label: r.name,
        category: 'Automations',
        subtitle: r.triggerSummary(),
        icon: Icons.auto_awesome_outlined,
        onRun: (context) => context.go('/automations/${r.id}'),
      ),
  ];
}

/// Opens the palette on Cmd-K / Ctrl-K anywhere inside it.
class CommandPaletteScope extends ConsumerWidget {
  const CommandPaletteScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _OpenPaletteIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _OpenPaletteIntent(),
      },
      child: Actions(
        actions: {
          _OpenPaletteIntent: CallbackAction<_OpenPaletteIntent>(
            onInvoke: (_) {
              showCommandPalette(context, ref);
              return null;
            },
          ),
        },
        // Without this the shortcut only fires once something inside has been
        // clicked — the shell must hold focus from the first frame.
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}

class _OpenPaletteIntent extends Intent {
  const _OpenPaletteIntent();
}

Future<void> showCommandPalette(BuildContext context, WidgetRef ref) =>
    showDialog<void>(
      context: context,
      builder: (_) => _Palette(commands: buildCommands(ref)),
    );

class _Palette extends StatefulWidget {
  const _Palette({required this.commands});

  final List<Command> commands;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  String _query = '';
  int _cursor = 0;

  List<Command> get _matches {
    if (_query.isEmpty) {
      // Everything at once would be 200+ rows; lead with the destinations.
      return widget.commands.where((c) => c.category == 'Go to').toList();
    }
    final q = _query.toLowerCase();
    return widget.commands
        .where((c) =>
            c.label.toLowerCase().contains(q) ||
            (c.subtitle?.toLowerCase().contains(q) ?? false))
        .take(40)
        .toList();
  }

  void _run(Command c) {
    Navigator.pop(context);
    c.onRun(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final matches = _matches;
    final cursor = _cursor.clamp(0, matches.isEmpty ? 0 : matches.length - 1);

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 96, left: 16, right: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 480),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                setState(() => _cursor = cursor + 1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                setState(() => _cursor = cursor - 1),
            const SingleActivator(LogicalKeyboardKey.enter): () {
              if (matches.isNotEmpty) _run(matches[cursor]);
            },
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(t.space.md),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Jump to a device, a rule, a page…',
                    border: InputBorder.none,
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                  onChanged: (v) => setState(() {
                    _query = v;
                    _cursor = 0;
                  }),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: matches.isEmpty
                    ? Padding(
                        padding: EdgeInsets.all(t.space.lg),
                        child: Text('Nothing matches “$_query”.',
                            style: TextStyle(color: t.surface.onBaseMuted)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: matches.length,
                        itemBuilder: (context, i) {
                          final c = matches[i];
                          return ListTile(
                            dense: true,
                            selected: i == cursor,
                            selectedTileColor:
                                t.accent.primary.withValues(alpha: 0.10),
                            leading: Icon(c.icon, size: 18),
                            title: Text(c.label),
                            subtitle:
                                c.subtitle == null ? null : Text(c.subtitle!),
                            trailing: Text(
                              c.category,
                              style: TextStyle(
                                fontSize: 11,
                                color: t.surface.onBaseMuted,
                              ),
                            ),
                            onTap: () => _run(c),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
