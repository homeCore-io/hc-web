import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/automations_provider.dart';
import '../../core/rules/node.dart';
import '../../core/rules/rule.dart';
import '../../core/rules/schema.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/components/hc_sentence.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';
import 'rule_phrasing.dart';
import 'widgets/device_trigger_picker.dart';
import 'widgets/node_trees.dart';
import 'widgets/rule_outline_pane.dart';
import 'widgets/editor_style.dart';
import 'widgets/rule_refs.dart';
import 'widgets/sentence_editor.dart';

/// The rule editor.
///
/// Every form below is generated from the descriptors in `core/rules/schema.dart`
/// — there is no per-variant form code anywhere in this file. That is what lets
/// one page cover 18 triggers, 13 conditions and 34 actions, *including* the
/// recursive ones (`Not`/`And`/`Or`/`Xor`, `Conditional`, `Parallel`, `Repeat*`)
/// that the previous editor dropped into a raw JSON textarea.
class AutomationEditorPage extends ConsumerStatefulWidget {
  const AutomationEditorPage({super.key, required this.ruleId});

  /// A rule UUID, or `'new'`.
  final String? ruleId;

  @override
  ConsumerState<AutomationEditorPage> createState() =>
      _AutomationEditorPageState();
}

class _AutomationEditorPageState extends ConsumerState<AutomationEditorPage> {
  HcRule? _rule;
  bool _dirty = false;
  bool _saving = false;

  /// Comparison pane, off until asked for.
  bool _showOutline = false;
  String? _saveError;

  /// Dry-run outcomes, positionally aligned with the condition list.
  List<ConditionResult>? _testResults;
  bool? _wouldFire;

  bool get _isNew => widget.ruleId == null || widget.ruleId == 'new';

  void _touch() => setState(() => _dirty = true);

  void _goBack() =>
      context.canPop() ? context.pop() : context.go('/automations');

  @override
  Widget build(BuildContext context) {
    final rulesAsync = ref.watch(automationsProvider);
    final refs = ref.watch(ruleRefsProvider);

    // Seed the working copy once, as a deep copy — abandoning the editor must
    // not leave half-applied edits in the cached list.
    if (_rule == null) {
      if (_isNew) {
        _rule = HcRule(id: '', name: '', trigger: HcNode('ManualTrigger'));
      } else {
        if (rulesAsync.isLoading) {
          return SectionScaffold(
            title: 'Automations',
            onBack: _goBack,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        final found = rulesAsync.valueOrNull
            ?.where((r) => r.id == widget.ruleId)
            .firstOrNull;
        if (found == null) {
          return SectionScaffold(
            title: 'Automations',
            onBack: _goBack,
            child: Center(
              child: Text('Rule not found.',
                  style: TextStyle(
                      color: HcTokens.of(context).surface.onBaseMuted)),
            ),
          );
        }
        _rule = found.copy();
      }
    }

    final rule = _rule!;

    // The header says where you ARE ("Automations"); the rule's own name is the
    // page's title, in the body, so it is never printed twice.
    return SectionScaffold(
      title: 'Automations',
      onBack: _goBack,
      actions: [
        // The outline pane is a comparison, not a replacement: it is off by
        // default and shows the same rule beside the tree so the two can be
        // judged on real rules rather than a mockup.
        Builder(builder: (ctx) {
          final tt = HcTokens.of(ctx);
          final on = _showOutline;
          return TextButton.icon(
            onPressed: () => setState(() => _showOutline = !_showOutline),
            icon: Icon(Icons.account_tree_outlined,
                size: 15,
                color: on ? tt.accent.active : tt.surface.onBaseMuted),
            label: Text('Outline',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: on ? tt.accent.active : tt.surface.onBaseMuted)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          );
        }),
        if (!_isNew)
          Builder(builder: (ctx) {
            final tt = HcTokens.of(ctx);
            return TextButton(
              onPressed: _saving ? null : _test,
              style: TextButton.styleFrom(
                foregroundColor: tt.surface.onBaseMuted,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              child: const Text('Dry run',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            );
          }),
      ],
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              // Side by side only where there is room for both to be read;
              // narrower than this and the outline would squeeze the editor it
              // is supposed to be compared against.
              final wide = box.maxWidth >= 1100;
              final editor = _editorList(context, rule);
              if (!_showOutline || !wide) return editor;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: editor),
                  // Full height, so the pane is a column beside the editor
                  // rather than a card floating at the top of one.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 16, 20, 24),
                    child: SizedBox(
                      width: 360,
                      child: RuleOutlinePane(rule: rule, refs: refs),
                    ),
                  ),
                ],
              );
            }),
          ),
          // Save arrives when there is something to save, and leaves when there
          // isn't — an app tells you when you have something to lose.
          _SaveBar(
            visible: _dirty || _isNew,
            saving: _saving,
            onSave: _saving ? null : _save,
            onDiscard: _saving ? null : _goBack,
          ),
        ],
      ),
    );
  }

  // -- header --------------------------------------------------------------

  /// The rule's name, as a title you type into — not a labelled box.
  ///
  /// The name is the only one of these five fields anyone edits more than once,
  /// so it gets the weight of a heading and the other four get demoted to the
  /// meta line below. They used to be three outlined `TextFormField`s and a
  /// `Switch` given exactly as much visual weight as the rule's own name, which
  /// is how a rule ended up looking like a settings screen.
  Widget _ruleHeader(HcRule rule) {
    final t = HcTokens.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(0, t.space.sm, 0, t.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: rule.name,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              color: t.surface.onBase,
            ),
            decoration: InputDecoration(
              hintText: 'Name this automation',
              hintStyle: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                color: t.surface.onBaseMuted.withValues(alpha: 0.4),
              ),
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            onChanged: (v) {
              rule.name = v;
              _touch();
            },
          ),
          SizedBox(height: t.space.sm),
          _MetaLine(rule: rule, onChanged: _touch),
        ],
      ),
    );
  }

  // -- trigger -------------------------------------------------------------

  Widget _triggerEditor(HcRule rule, RuleRefs refs) => NodeBody(
        node: rule.trigger,
        registry: kTriggers,
        refs: refs,
        onChanged: _touch,
        phraseFor: (n) => _withLiveSummary(triggerPhrase(n), n, refs),
        size: HcSentenceSize.large,
        // A rule has exactly one trigger, so swapping it is a *replace*, not an
        // add — and it lives on the sentence rather than above it.
        trailing: IconButton(
          tooltip: 'Change the trigger',
          icon: const Icon(Icons.swap_horiz, size: 17),
          onPressed: () async {
            final picked = await showDialog<HcNode>(
              context: context,
              builder: (_) => DeviceTriggerPicker(refs: refs),
            );
            if (picked != null) {
              rule.trigger = picked;
              _touch();
            }
          },
        ),
      );

  /// Glosses the trigger with what the device is doing *right now*.
  ///
  /// A rule that says "when the Bathroom Door Sensor closes" is more useful when
  /// it also says "currently closed · 14:02" — you can see whether it is armed.
  Phrase? _withLiveSummary(Phrase? p, HcNode n, RuleRefs refs) {
    if (p == null) return null;

    // EVERY device the trigger watches, not just the first. The gloss used to
    // read `currently closed · dining_room.dining_room_door_sensor` beneath a
    // sentence naming four doors — the same lie the sentence had just stopped
    // telling, in smaller type.
    final devices = [
      for (final ref in devicesOf(n))
        if (refs.deviceFor(ref) case final d?) d,
    ];
    if (devices.isEmpty) return p;

    final attr = n['attribute'] as String?;
    final offline = devices.where((d) => !d.available).toList();

    // One device: say exactly what it is doing. Several: say whether they AGREE,
    // because "3 of 4 open" is the fact you actually want when a rule fires on
    // any of them.
    String gloss;
    if (devices.length == 1) {
      final d = devices.single;
      gloss = !d.available
          ? 'offline'
          : (attr != null && d.state.containsKey(attr))
              ? 'currently ${_say(attr, d.state[attr])}'
              : (d.canonicalName ?? d.id);
    } else if (attr == null) {
      gloss = '${devices.length} devices';
    } else {
      final known =
          devices.where((d) => d.available && d.state.containsKey(attr));
      final values = known.map((d) => _say(attr, d.state[attr])).toSet();
      gloss = values.length == 1
          ? 'all ${devices.length} currently ${values.single}'
          : known
              .map((d) => '${d.displayName}: ${_say(attr, d.state[attr])}')
              .join(' · ');
    }

    if (offline.isNotEmpty) {
      gloss = '$gloss · ${offline.length} offline';
    }
    return Phrase(p.parts, summary: gloss);
  }

  static String _say(String attr, Object? v) => switch ((attr, v)) {
        ('open', true) => 'open',
        ('open', false) => 'closed',
        ('on', true) => 'on',
        ('on', false) => 'off',
        ('locked', true) => 'locked',
        ('locked', false) => 'unlocked',
        _ => '$v',
      };

  /// True when the trigger's device already sits at the value the rule waits for.
  bool _triggerIsLive(HcRule rule, RuleRefs refs) {
    final n = rule.trigger;
    final ref = n['device_id'] as String?;
    final attr = n['attribute'] as String?;
    if (ref == null || attr == null) return false;

    final d = refs.deviceFor(ref);
    if (d == null || !d.available) return false;

    final want = n['to'];
    // No target value means "any change", which is never *currently* true.
    return want != null && d.state[attr] == want;
  }

  // -- advanced ------------------------------------------------------------

  Widget _advanced(HcRule rule) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: rule.requiredExpression ?? '',
            decoration: const InputDecoration(
              labelText: 'Required expression',
              helperText: 'Rhai boolean. Gates the rule before the trigger is '
                  'even considered.',
              helperMaxLines: 2,
              isDense: true,
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontFamily: 'monospace'),
            onChanged: (v) {
              rule.requiredExpression = v.isEmpty ? null : v;
              _touch();
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: rule.triggerCondition ?? '',
            decoration: const InputDecoration(
              labelText: 'Trigger condition',
              helperText:
                  'Rhai boolean. Runs after the trigger, before the conditions.',
              helperMaxLines: 2,
              isDense: true,
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontFamily: 'monospace'),
            onChanged: (v) {
              rule.triggerCondition = v.isEmpty ? null : v;
              _touch();
            },
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: rule.cancelOnFalse,
            title: const Text('Cancel pending delays when the gate goes false'),
            onChanged: (v) {
              rule.cancelOnFalse = v ?? false;
              _touch();
            },
          ),
          const Divider(),
          Text('Logging', style: Theme.of(context).textTheme.labelLarge),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: rule.logTriggers,
            title: const Text('Log triggers'),
            onChanged: (v) {
              rule.logTriggers = v ?? false;
              _touch();
            },
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: rule.logActions,
            title: const Text('Log actions'),
            onChanged: (v) {
              rule.logActions = v ?? false;
              _touch();
            },
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: rule.logEvents,
            title: const Text('Log events'),
            onChanged: (v) {
              rule.logEvents = v ?? false;
              _touch();
            },
          ),
        ],
      );

  // -- banners -------------------------------------------------------------

  /// The editor itself — the scrolling clause list, unchanged. Extracted so the
  /// outline pane can sit beside it without either knowing about the other.
  Widget _editorList(BuildContext context, HcRule rule) {
    final refs = ref.watch(ruleRefsProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        // Core sets `error` on a rule whose file failed to parse or
        // whose devices were deleted. It never executes — say so loudly.
        if (rule.hasError) _banner(context, rule.error!, isError: true),
        if (_saveError != null) _banner(context, _saveError!, isError: true),
        if (_wouldFire != null) _testBanner(context),
        _ruleHeader(rule),

        // The clauses read down the page as one sentence about the
        // house, joined by a rail. There is no card around them: a card
        // says "this is a form", and a rule is a paragraph.
        HcClause(
          label: 'When',
          // The rail node lights when the trigger's device is already in
          // the state the rule waits for, so a rule shows you where the
          // house actually IS, standing still.
          live: _triggerIsLive(rule, refs),
          child: _triggerEditor(rule, refs),
        ),
        HcClause(
          label: 'And if',
          child: ConditionTree(
            conditions: rule.conditions,
            refs: refs,
            results: _testResults,
            onChanged: _touch,
          ),
        ),
        HcClause(
          label: 'Then',
          last: true,
          child: ActionTree(
            actions: rule.actions,
            refs: refs,
            onChanged: _touch,
          ),
        ),
        const SizedBox(height: 8),
        _Section(
          title: 'Advanced',
          initiallyExpanded: false,
          child: _advanced(rule),
        ),
      ],
    );
  }

  Widget _banner(BuildContext context, String message, {bool isError = false}) {
    final t = HcTokens.of(context);
    final c = isError ? t.accent.danger : t.surface.onBaseMuted;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: isError ? 0.4 : 0.25)),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.info_outline,
              size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(message,
                style: TextStyle(fontSize: 13, color: t.surface.onBase)),
          ),
        ],
      ),
    );
  }

  Widget _testBanner(BuildContext context) {
    final t = HcTokens.of(context);
    final fire = _wouldFire == true;
    final c = fire ? t.accent.success : t.surface.onBaseMuted;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(fire ? Icons.check_circle_outline : Icons.block,
              size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fire
                  ? 'As things stand right now, this rule would fire.'
                  : 'As things stand right now, this rule would not fire — the '
                      'failing condition is marked below.',
              style: TextStyle(fontSize: 13, color: t.surface.onBase),
            ),
          ),
        ],
      ),
    );
  }

  // -- commands ------------------------------------------------------------

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await ref.read(automationsProvider.notifier).save(_rule!);
      if (!mounted) return;
      final wasNew = _isNew;
      setState(() {
        _rule = saved.copy();
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved.')));
      // A new rule gets its UUID from core, so land on the real route.
      if (wasNew) context.go('/automations/${saved.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = _describe(e);
      });
    }
  }

  Future<void> _test() async {
    try {
      final result =
          await ref.read(automationsApiProvider).testRule(widget.ruleId!);
      if (!mounted) return;
      setState(() {
        _wouldFire = result['would_fire'] as bool?;
        _testResults = [
          for (final c in (result['conditions'] as List? ?? const []))
            ConditionResult.fromJson(c as Map),
        ];
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Test failed: ${_describe(e)}')),
      );
    }
  }

  /// Core's rejections are specific and useful ("invalid rule body: expected
  /// map with a single key"), so show the server's own words rather than
  /// burying them under a generic failure message.
  String _describe(Object e) {
    final s = '$e';
    final match = RegExp(r'"error":"(.*?)"').firstMatch(s);
    return match?.group(1) ?? s;
  }
}

/// Trigger picker, grouped by the category each trigger declares.
/// The unsaved-changes bar.
///
/// It slides up the moment the rule differs from what the server holds, and it
/// is the only place Save exists. That is the difference between an app and a
/// form: a form shows you a disabled Save button forever, an app tells you when
/// you have something to lose.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.visible,
    required this.saving,
    required this.onSave,
    required this.onDiscard,
  });

  final bool visible;
  final bool saving;
  final VoidCallback? onSave;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 1),
      duration: t.motion.base,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: t.motion.base,
        child: Container(
          padding: EdgeInsets.fromLTRB(
              t.space.md, t.space.sm, t.space.md, t.space.sm),
          decoration: BoxDecoration(
            color: t.surface.raised,
            border: Border(top: BorderSide(color: t.stroke.hairline)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.accent.warn,
                  ),
                ),
                SizedBox(width: t.space.sm),
                Text(
                  'Unsaved changes',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.surface.onBase,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onDiscard,
                  child: Text(
                    'Discard',
                    style: TextStyle(color: t.surface.onBaseMuted),
                  ),
                ),
                SizedBox(width: t.space.xs),
                FilledButton(
                  onPressed: onSave,
                  child: saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Everything about the rule that is not its name, said in one line.
///
/// Priority, cooldown and run mode are set once and then forgotten, so they read
/// as prose and open an editor when tapped rather than occupying three permanent
/// labelled boxes. The line states the *effect* — "at most once every 5 min" —
/// not the field name and its raw value.
class _MetaLine extends ConsumerWidget {
  const _MetaLine({required this.rule, required this.onChanged});

  final HcRule rule;
  final VoidCallback onChanged;

  static String _cooldown(int? secs) {
    if (secs == null || secs == 0) return 'no cooldown';
    if (secs % 3600 == 0) {
      final h = secs ~/ 3600;
      return 'at most once every $h ${h == 1 ? 'hour' : 'hours'}';
    }
    if (secs % 60 == 0) {
      final m = secs ~/ 60;
      return 'at most once every $m ${m == 1 ? 'minute' : 'minutes'}';
    }
    return 'at most once every ${secs}s';
  }

  static String _runMode(RunMode m) => switch (m.kind) {
        'Queued' => 'queue up to ${m.maxQueue}',
        'Parallel' => 'run in parallel',
        'Restart' => 'restart if re-triggered',
        _ => 'one run at a time',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    // Tags already existed end to end — core stores them, the API filters on
    // them, and the list groups by them — with nothing anywhere to set one.
    // Thirty of thirty-four rules sat under "Untagged" because tagging a rule
    // meant editing its RON file by hand.
    final known = <String>{
      for (final r in ref.watch(automationsProvider).valueOrNull ?? const [])
        ...r.tags,
    }.toList()
      ..sort();

    return Wrap(
      spacing: t.space.xs,
      runSpacing: t.space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Enabled is the one meta field with a consequence you care about at a
        // glance, so it keeps a colour and a dot. The rest are grey.
        _MetaChip(
          label: rule.enabled ? 'Enabled' : 'Disabled',
          lit: rule.enabled,
          dot: true,
          onTap: () {
            rule.enabled = !rule.enabled;
            onChanged();
          },
        ),
        _dot(t),
        _MetaChip(
          label: rule.priority == 0
              ? 'normal priority'
              : 'priority ${rule.priority}',
          onTap: () => _editNumber(
            context,
            title: 'Priority',
            help: 'Higher runs first. −1000 to 1000.',
            value: rule.priority,
            onSet: (v) {
              rule.priority = (v ?? 0).clamp(-1000, 1000);
              onChanged();
            },
          ),
        ),
        _dot(t),
        _MetaChip(
          label: _cooldown(rule.cooldownSecs),
          onTap: () => _editNumber(
            context,
            title: 'Cooldown (seconds)',
            help: 'Leave empty for none.',
            value: rule.cooldownSecs,
            nullable: true,
            onSet: (v) {
              rule.cooldownSecs = v;
              onChanged();
            },
          ),
        ),
        _dot(t),
        _MetaChip(
          label: _runMode(rule.runMode),
          onTap: () => _editRunMode(context),
        ),
        _dot(t),
        // Each tag is its own chip so removing one is a single tap, rather
        // than editing a comma-separated string and hoping.
        for (final tag in rule.tags)
          _MetaChip(
            label: tag,
            lit: true,
            icon: Icons.local_offer_outlined,
            onTap: () {
              rule.tags.remove(tag);
              onChanged();
            },
          ),
        _MetaChip(
          label: rule.tags.isEmpty ? 'add a tag' : 'add',
          icon: Icons.add,
          onTap: () => _addTag(context, known),
        ),
      ],
    );
  }

  /// Add a tag, offering the ones already in use.
  ///
  /// Offering them is the point: tags only group rules if they are spelled the
  /// same, and a free text box produces "deck", "Deck" and "decks" within a
  /// week. Typing a new one is still allowed — that is how the first of any
  /// tag gets created.
  Future<void> _addTag(BuildContext context, List<String> known) async {
    final controller = TextEditingController();
    final available = known.where((k) => !rule.tags.contains(k)).toList();

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final t = HcTokens.of(ctx);
        return HcDialog(
          title: 'Add a tag',
          description: 'Tags group rules on the automations list.',
          width: 420,
          actions: [
            HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
            HcButton(
              label: 'Add',
              kind: HcButtonKind.primary,
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (available.isNotEmpty) ...[
                const RailLabel('Already in use'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in available)
                      ActionChip(
                        label: Text(k),
                        onPressed: () => Navigator.pop(ctx, k),
                      ),
                  ],
                ),
                SizedBox(height: t.space.md),
              ],
              const RailLabel('Or a new one'),
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                autofocus: available.isEmpty,
                decoration:
                    fieldDecoration(t, hint: 'deck, vacation, security'),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();

    final tag = picked?.trim();
    if (tag == null || tag.isEmpty || rule.tags.contains(tag)) return;
    rule.tags.add(tag);
    rule.tags.sort();
    onChanged();
  }

  Widget _dot(HcTokens t) => Text(
        '·',
        style: TextStyle(color: t.surface.onBaseMuted.withValues(alpha: 0.5)),
      );

  Future<void> _editNumber(
    BuildContext context, {
    required String title,
    required String help,
    required int? value,
    required ValueChanged<int?> onSet,
    bool nullable = false,
  }) async {
    final controller = TextEditingController(text: value?.toString() ?? '');

    await showDialog<void>(
      context: context,
      builder: (ctx) => HcDialog(
        title: title,
        description: help,
        actions: [
          HcButton(
            label: 'Done',
            kind: HcButtonKind.primary,
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
        child: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          onSubmitted: (_) => Navigator.pop(ctx),
        ),
      ),
    );

    final text = controller.text.trim();
    if (text.isEmpty && nullable) {
      onSet(null);
    } else {
      final parsed = int.tryParse(text);
      if (parsed != null) onSet(parsed);
    }
    controller.dispose();
  }

  Future<void> _editRunMode(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final t = HcTokens.of(ctx);
          return HcDialog(
            title: 'When it fires again',
            actions: [
              HcButton(
                label: 'Done',
                kind: HcButtonKind.primary,
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final k in RunMode.kinds)
                  InkWell(
                    onTap: () {
                      rule.runMode =
                          RunMode(k, maxQueue: rule.runMode.maxQueue);
                      setInner(() {});
                      onChanged();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            rule.runMode.kind == k
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: rule.runMode.kind == k
                                ? t.accent.active
                                : t.surface.onBaseMuted,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _runMode(
                                RunMode(k, maxQueue: rule.runMode.maxQueue)),
                            style: TextStyle(
                                fontSize: 13.5, color: t.surface.onBase),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (rule.runMode.kind == 'Queued') ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: '${rule.runMode.maxQueue}',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Max queued'),
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n == null) return;
                      rule.runMode = RunMode('Queued', maxQueue: n);
                      setInner(() {});
                      onChanged();
                    },
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.onTap,
    this.lit = false,
    this.dot = false,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final bool lit;
  final bool dot;

  /// A leading glyph, for chips whose label alone does not say what kind of
  /// thing they are. A tag reading `deck` sits next to `run in parallel` and
  /// is otherwise indistinguishable from a setting.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    // `lit` used to be read only alongside `dot`, so a chip that set it
    // without one rendered in the same grey as everything else — which is how
    // the tag chips ended up invisible among the settings.
    //
    // With a dot it means "this state is good" (enabled → green). Without one
    // it means "this is content, not a setting", and takes the same accent
    // the automations list gives a tag group heading, so the same tag is the
    // same colour in both places.
    final colour = lit
        ? (dot ? t.accent.success : t.accent.active)
        : t.surface.onBaseMuted;

    return InkWell(
      onTap: onTap,
      borderRadius: t.radius.smR,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: t.space.xs,
          vertical: 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot) ...[
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: colour),
              ),
              SizedBox(width: t.space.xs),
            ],
            if (icon != null) ...[
              Icon(icon, size: 12, color: colour),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: colour,
                fontWeight: dot ? FontWeight.w600 : FontWeight.w400,
                fontFeatures: t.numericFontFeatures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled block on a token surface. Advanced starts collapsed — but the
/// clauses above it never do: a rule you cannot see all of is one you get wrong.
class _Section extends StatefulWidget {
  const _Section({
    required this.title,
    required this.child,
    this.initiallyExpanded = true,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: t.surface.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Text(widget.title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: t.surface.onBase)),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: t.motion.fast,
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: t.surface.onBaseMuted),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

/// Test seam for the rule meta line.
///
/// The tag controls live on it, and pumping the whole editor page would drag
/// in every provider the page touches to test four chips.
class RuleMetaLineTestAccess extends StatelessWidget {
  const RuleMetaLineTestAccess({
    super.key,
    required this.rule,
    required this.onChanged,
  });

  final HcRule rule;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) =>
      _MetaLine(rule: rule, onChanged: onChanged);
}
