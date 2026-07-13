import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/automations_provider.dart';
import '../../core/rules/node.dart';
import '../../core/rules/rule.dart';
import '../../core/rules/schema.dart';
import 'widgets/field_editors.dart';
import 'widgets/node_trees.dart';
import 'widgets/rule_refs.dart';

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
  String? _saveError;

  /// Dry-run outcomes, positionally aligned with the condition list.
  List<ConditionResult>? _testResults;
  bool? _wouldFire;

  bool get _isNew => widget.ruleId == null || widget.ruleId == 'new';

  void _touch() => setState(() => _dirty = true);

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
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final found = rulesAsync.valueOrNull
            ?.where((r) => r.id == widget.ruleId)
            .firstOrNull;
        if (found == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Automation')),
            body: const Center(child: Text('Rule not found.')),
          );
        }
        _rule = found.copy();
      }
    }

    final rule = _rule!;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew
            ? 'New automation'
            : (rule.name.isEmpty ? 'Automation' : rule.name)),
        actions: [
          if (!_isNew)
            TextButton.icon(
              icon: const Icon(Icons.science_outlined, size: 18),
              label: const Text('Test'),
              onPressed: _saving ? null : _test,
            ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save'),
            onPressed: _saving || !_dirty ? null : _save,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Core sets `error` on a rule whose file failed to parse or whose
          // devices were deleted. Such a rule never executes — say so loudly.
          if (rule.hasError) _banner(context, rule.error!, isError: true),
          if (_saveError != null) _banner(context, _saveError!, isError: true),
          if (_wouldFire != null) _testBanner(context),
          _Section(title: 'Rule', child: _ruleHeader(rule)),
          _Section(
            title: 'When',
            subtitle: 'A rule has exactly one trigger.',
            child: _triggerEditor(rule, refs),
          ),
          _Section(
            title: 'And if',
            subtitle:
                'Every condition must pass. Use ANY / NOT for richer logic.',
            child: ConditionTree(
              conditions: rule.conditions,
              refs: refs,
              results: _testResults,
              onChanged: _touch,
            ),
          ),
          _Section(
            title: 'Then',
            child: ActionTree(
              actions: rule.actions,
              refs: refs,
              onChanged: _touch,
            ),
          ),
          _Section(
            title: 'Advanced',
            initiallyExpanded: false,
            child: _advanced(rule),
          ),
        ],
      ),
    );
  }

  // -- header --------------------------------------------------------------

  Widget _ruleHeader(HcRule rule) => Column(
        children: [
          TextFormField(
            initialValue: rule.name,
            decoration: const InputDecoration(
              labelText: 'Name',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              rule.name = v;
              _touch();
            },
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: '${rule.priority}',
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    helperText: 'Higher runs first. −1000 to 1000.',
                    helperMaxLines: 2,
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final p = int.tryParse(v);
                    if (p != null) {
                      rule.priority = p;
                      _touch();
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: rule.cooldownSecs?.toString() ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Cooldown (s)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    rule.cooldownSecs = v.isEmpty ? null : int.tryParse(v);
                    _touch();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _runModeField(rule)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch(
                value: rule.enabled,
                onChanged: (v) {
                  rule.enabled = v;
                  _touch();
                },
              ),
              Text(rule.enabled ? 'Enabled' : 'Disabled'),
            ],
          ),
        ],
      );

  Widget _runModeField(HcRule rule) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: rule.runMode.kind,
            decoration: const InputDecoration(
              labelText: 'Run mode',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final k in RunMode.kinds)
                DropdownMenuItem(value: k, child: Text(k)),
            ],
            onChanged: (v) {
              if (v == null) return;
              rule.runMode = RunMode(v, maxQueue: rule.runMode.maxQueue);
              _touch();
            },
          ),
          if (rule.runMode.kind == 'Queued')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextFormField(
                initialValue: '${rule.runMode.maxQueue}',
                decoration: const InputDecoration(
                  labelText: 'Max queue',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null) {
                    rule.runMode = RunMode('Queued', maxQueue: n);
                    _touch();
                  }
                },
              ),
            ),
        ],
      );

  // -- trigger -------------------------------------------------------------

  Widget _triggerEditor(HcRule rule, RuleRefs refs) {
    final variant = kTriggers[rule.trigger.tag];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                variant?.label ?? rule.trigger.tag,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.swap_horiz, size: 16),
              label: const Text('Change'),
              onPressed: () async {
                final picked = await showDialog<HcVariant>(
                  context: context,
                  builder: (_) => _TriggerPalette(current: rule.trigger.tag),
                );
                if (picked != null && picked.tag != rule.trigger.tag) {
                  rule.trigger = HcNode.blank(picked);
                  _touch();
                }
              },
            ),
          ],
        ),
        if (variant?.help != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Text(
              variant!.help!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
        const SizedBox(height: 8),
        if (variant != null)
          NodeFields(
            variant: variant,
            fields: rule.trigger.fields,
            refs: refs,
            onChanged: _touch,
          ),
      ],
    );
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

  Widget _banner(BuildContext context, String message, {bool isError = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? scheme.errorContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.info_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(message)),
        ],
      ),
    );
  }

  Widget _testBanner(BuildContext context) {
    final fire = _wouldFire == true;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (fire ? scheme.primary : scheme.outline).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(fire ? Icons.check_circle_outline : Icons.block, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(fire
                ? 'As things stand right now, this rule would fire.'
                : 'As things stand right now, this rule would not fire — the '
                    'failing condition is marked below.'),
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
class _TriggerPalette extends StatelessWidget {
  const _TriggerPalette({required this.current});

  final String current;

  @override
  Widget build(BuildContext context) => Dialog(
        child: SizedBox(
          width: 520,
          height: 560,
          child: ListView(
            children: [
              for (final category in kTriggerCategories) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    category.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                  ),
                ),
                for (final v
                    in kTriggers.values.where((v) => v.category == category))
                  ListTile(
                    dense: true,
                    selected: v.tag == current,
                    title: Text(v.label),
                    subtitle: v.help == null ? null : Text(v.help!),
                    onTap: () => Navigator.pop(context, v),
                  ),
              ],
            ],
          ),
        ),
      );
}

/// A titled block. Only Advanced collapses — a rule you cannot see all of is a
/// rule you will get wrong.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.subtitle,
    this.initiallyExpanded = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: child,
    );

    if (!initiallyExpanded) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: ExpansionTile(
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          children: [body],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
              ],
            ),
          ),
          body,
        ],
      ),
    );
  }
}
