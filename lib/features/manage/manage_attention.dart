import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/audit_api.dart';
import '../../core/devices/orphans.dart';
import '../../core/models/device_state.dart';
import '../../core/models/plugin_entry.dart';
import '../../core/rules/rule.dart';
import '../../core/providers/audit_provider.dart';
import '../../core/providers/automations_provider.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/plugins_provider.dart';
import '../../core/providers/stale_refs_provider.dart';

/// How loudly a finding asks.
enum AttentionLevel { bad, warn }

/// One thing that is wrong, said plainly, with the place that fixes it.
///
/// [headline] is the finding — a whole sentence, because "3 stale refs" is a
/// label and not a statement anybody can act on. [detail] says why it matters,
/// which is usually the part that makes someone bother. [route] is where the
/// fix lives, so the finding and its remedy are one tap apart rather than a
/// hunt through Manage.
class Attention {
  const Attention({
    required this.level,
    required this.headline,
    required this.detail,
    required this.action,
    required this.route,
  });

  final AttentionLevel level;
  final String headline;
  final String detail;
  final String action;
  final String route;
}

/// Denied audit entries since midnight, counted on their own.
///
/// A separate one-off query rather than a read of [auditProvider]: that is a
/// single shared notifier holding the Audit screen's filter, so counting
/// through it would mean either changing what that screen is showing or
/// reporting whatever it happened to be filtered to.
final deniedTodayProvider = FutureProvider.autoDispose<int>((ref) async {
  final now = DateTime.now();
  final rows = await ref.watch(auditApiProvider).list(
        AuditFilter(
          result: 'denied',
          from: DateTime(now.year, now.month, now.day),
          limit: 500,
        ),
      );
  return rows.length;
});

/// Everything wrong with the house right now, worst first.
///
/// Reads nothing itself so the rules below can be tested: what counts as a
/// finding, how it is worded, and — the easy one to get wrong — that a check
/// which has not answered yet produces no finding rather than a clean bill.
///
/// Every item comes from something the app already knows. There is
/// deliberately no "you have never backed up" item, which the design called
/// for: core exposes `POST /system/backup` and nothing that says when one last
/// happened, so the honest options were to invent a fact or leave it out.
List<Attention> buildAttention({
  List<HcRule>? rules,
  List<DeviceState>? devices,
  List<PluginEntry>? plugins,
  int? staleRefs,
  int? deniedToday,
}) {
  final items = <Attention>[];

  if (staleRefs != null && staleRefs > 0) {
    items.add(Attention(
      level: AttentionLevel.bad,
      headline: staleRefs == 1
          ? '1 automation points at a device that no longer exists.'
          : '$staleRefs automations point at devices that no longer exist.',
      detail: 'They fail silently every time they fire.',
      action: 'Review',
      route: '/admin/maintenance',
    ));
  }

  if (rules != null) {
    final broken = rules.where((r) => r.hasError).length;
    if (broken > 0) {
      items.add(Attention(
        level: AttentionLevel.bad,
        headline: broken == 1
            ? '1 automation failed to load.'
            : '$broken automations failed to load.',
        detail: 'A rule with an error never runs.',
        action: 'Automations',
        route: '/automations',
      ));
    }
    // Only when *everything* is off. A few disabled rules is housekeeping; the
    // whole set disabled means nothing in the house runs on a rule, which is
    // usually a surprise to whoever left it that way.
    final disabled = rules.where((r) => !r.enabled).length;
    if (rules.isNotEmpty && disabled == rules.length) {
      items.add(Attention(
        level: AttentionLevel.warn,
        headline: 'All ${rules.length} automations are disabled.',
        detail: 'Nothing in the house is running on a rule right now.',
        action: 'Automations',
        route: '/automations',
      ));
    }
  }

  if (plugins != null) {
    final offline = plugins.where((p) => p.isOffline).length;
    if (offline > 0) {
      items.add(Attention(
        level: AttentionLevel.bad,
        headline: offline == 1
            ? '1 plugin is offline.'
            : '$offline plugins are offline.',
        detail: 'Its devices stop answering and its rules stop firing.',
        action: 'Plugins',
        route: '/plugins',
      ));
    }
  }

  if (devices != null) {
    final orphans = orphanDevices(devices).length;
    if (orphans > 0) {
      items.add(Attention(
        level: AttentionLevel.warn,
        headline: orphans == 1
            ? '1 device has no plugin behind it.'
            : '$orphans devices have no plugin behind them.',
        detail: 'They sit in every picker and every rule that names them.',
        action: 'Review',
        route: '/admin/maintenance',
      ));
    }
  }

  if (deniedToday != null && deniedToday > 0) {
    items.add(Attention(
      level: AttentionLevel.warn,
      headline: deniedToday == 1
          ? '1 sign-in was denied today.'
          : '$deniedToday sign-ins were denied today.',
      detail: 'Check who was trying, and from where.',
      action: 'Audit',
      route: '/admin/audit',
    ));
  }

  items.sort((a, b) => a.level.index.compareTo(b.level.index));
  return items;
}

/// [buildAttention] over the live providers.
List<Attention> attentionItems(WidgetRef ref) => buildAttention(
      rules: ref.watch(automationsProvider).valueOrNull,
      devices: ref.watch(devicesProvider).valueOrNull,
      plugins: ref.watch(pluginsProvider).valueOrNull,
      staleRefs: ref.watch(staleRefsProvider).valueOrNull?.length,
      deniedToday: ref.watch(deniedTodayProvider).valueOrNull,
    );
