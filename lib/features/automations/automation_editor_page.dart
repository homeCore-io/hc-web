import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/device_state.dart';
import '../../core/models/mode_state.dart';
import '../../core/models/rule.dart';
import '../../core/providers/automations_provider.dart';
import '../../core/providers/name_resolver_provider.dart';

// ─── Summary helpers ─────────────────────────────────────────────────────────

String _triggerSummary(
  Map<String, dynamic> trigger,
  DeviceNameResolver dr,
  ModeNameResolver mr,
) {
  final type = trigger['type'] as String? ?? 'unknown';
  switch (type) {
    case 'device_state_changed':
      final primaryId = trigger['device_id'] as String? ?? '';
      final extraIds =
          (trigger['device_ids'] as List?)?.map((e) => e as String).toList() ??
              [];
      final allNames = [
        if (primaryId.isNotEmpty) dr.resolve(primaryId),
        ...extraIds.map(dr.resolve),
      ];
      final devStr =
          allNames.isEmpty ? '?' : allNames.join(', ');
      final attr = trigger['attribute'] as String?;
      final to = trigger['to'];
      if (attr != null && to != null) return 'Device $devStr: $attr → $to';
      if (attr != null) return 'Device $devStr: $attr changes';
      return 'Device $devStr changes';
    case 'device_availability_changed':
      final dev = dr.resolve(trigger['device_id'] as String? ?? '');
      final to = trigger['to'];
      if (to == true) return 'Device $dev comes online';
      if (to == false) return 'Device $dev goes offline';
      return 'Device $dev availability changes';
    case 'time_of_day':
      final time = trigger['time'] as String? ?? '?';
      final days = (trigger['days'] as List?)?.join(', ') ?? 'every day';
      return 'Time: $time ($days)';
    case 'sun_event':
      final event = trigger['event'] as String? ?? 'sunset';
      final offset = trigger['offset_minutes'] as int? ?? 0;
      if (offset == 0) return 'Sun: $event';
      return 'Sun: $event ${offset > 0 ? '+' : ''}${offset}min';
    case 'mode_changed':
      final modeId = trigger['mode_id'] as String?;
      final modeName = modeId != null ? mr.resolve(modeId) : 'any mode';
      final to = trigger['to'];
      if (to == true) return 'Mode $modeName turns on';
      if (to == false) return 'Mode $modeName turns off';
      return 'Mode $modeName changes';
    case 'webhook_received':
      return 'Webhook: ${trigger['path'] ?? '/'}';
    case 'manual_trigger':
      return 'Manual trigger';
    case 'mqtt_message':
      return 'MQTT: ${trigger['topic_pattern'] ?? ''}';
    case 'custom_event':
      return 'Event: ${trigger['event_type'] ?? ''}';
    case 'system_started':
      return 'System started';
    case 'cron':
      return 'Cron: ${trigger['expression'] ?? ''}';
    case 'periodic':
      final n = trigger['every_n'] ?? '?';
      final unit = trigger['unit'] ?? 'minutes';
      return 'Every $n $unit';
    case 'button_event':
      final dev = dr.resolve(trigger['device_id'] as String? ?? '');
      final event = trigger['event'] as String? ?? 'pushed';
      final btn = trigger['button_number'];
      return btn != null
          ? 'Button $btn on $dev: $event'
          : 'Button on $dev: $event';
    case 'numeric_threshold':
      final dev = dr.resolve(trigger['device_id'] as String? ?? '');
      final attr = trigger['attribute'] as String? ?? '';
      final op = trigger['op'] as String? ?? '';
      final val = trigger['value'];
      return 'Numeric: $dev.$attr $op $val';
    case 'hub_variable_changed':
      final name = trigger['name'] as String?;
      return name != null ? 'Variable "$name" changed' : 'Any variable changed';
    case 'calendar_event':
      final title = trigger['title_contains'] as String?;
      return title != null ? 'Calendar event containing "$title"' : 'Calendar event';
    default:
      return type;
  }
}

String _conditionSummary(
  Map<String, dynamic> cond,
  DeviceNameResolver dr,
  ModeNameResolver mr,
) {
  final type = cond['type'] as String? ?? 'unknown';
  switch (type) {
    case 'device_state':
      final dev = dr.resolve(cond['device_id'] as String? ?? '');
      final attr = cond['attribute'] as String? ?? '';
      final op = cond['op'] as String? ?? 'eq';
      final val = cond['value'];
      return '$dev.$attr $op $val';
    case 'mode_is':
      final modeId = cond['mode_id'] as String?;
      final modeName = modeId != null ? mr.resolve(modeId) : '';
      final on = cond['on'] as bool? ?? true;
      return 'Mode $modeName is ${on ? 'on' : 'off'}';
    case 'time_window':
      return 'Time between ${cond['start'] ?? '?'} and ${cond['end'] ?? '?'}';
    case 'hub_variable':
      final name = cond['name'] as String? ?? '';
      final op = cond['op'] as String? ?? 'eq';
      final val = cond['value'];
      return 'Variable "$name" $op $val';
    case 'script_expression':
      final script = cond['script'] as String? ?? '';
      return 'Script: ${script.length > 40 ? '${script.substring(0, 40)}…' : script}';
    case 'time_elapsed':
      final dev = dr.resolve(cond['device_id'] as String? ?? '');
      final attr = cond['attribute'] as String? ?? '';
      final secs = cond['duration_secs'];
      return '$dev.$attr unchanged for ${secs}s';
    case 'private_boolean_is':
      final name = cond['name'] as String? ?? '';
      final val = cond['value'] as bool? ?? true;
      return 'Bool "$name" is ${val ? 'true' : 'false'}';
    case 'not':
      final inner = cond['condition'] as Map<String, dynamic>?;
      if (inner == null) return 'NOT (?)';
      return 'NOT (${_conditionSummary(inner, dr, mr)})';
    case 'and':
      final nested =
          (cond['conditions'] as List?)?.length ?? 0;
      return 'AND ($nested conditions)';
    case 'or':
      final nested =
          (cond['conditions'] as List?)?.length ?? 0;
      return 'OR ($nested conditions)';
    case 'xor':
      final nested =
          (cond['conditions'] as List?)?.length ?? 0;
      return 'XOR ($nested conditions)';
    default:
      return type;
  }
}

String _actionSummary(Map<String, dynamic> action, DeviceNameResolver dr) {
  final type = action['type'] as String? ?? 'unknown';
  switch (type) {
    case 'set_device_state':
      final dev = dr.resolve(action['device_id'] as String? ?? '');
      final state = action['state'];
      return 'Set $dev → ${state != null ? jsonEncode(state) : '{}'}';
    case 'delay':
      final secs = action['duration_secs'] ?? 0;
      return 'Delay ${secs}s';
    case 'notify':
      final channel = action['channel'] as String? ?? '';
      final msg = action['message'] as String? ?? '';
      return 'Notify [$channel]: ${msg.length > 40 ? '${msg.substring(0, 40)}…' : msg}';
    case 'log_message':
      final level = action['level'] as String? ?? 'info';
      final msg = action['message'] as String? ?? '';
      return 'Log [$level]: ${msg.length > 40 ? '${msg.substring(0, 40)}…' : msg}';
    case 'fire_event':
      return 'Fire event: ${action['event_type'] ?? ''}';
    case 'comment':
      final text = action['text'] as String? ?? '';
      return '// ${text.length > 50 ? '${text.substring(0, 50)}…' : text}';
    case 'set_mode':
      return 'Set mode ${action['mode_id'] ?? ''}: ${action['command'] ?? 'on'}';
    case 'set_hub_variable':
      final name = action['name'] as String? ?? '';
      final op = action['op'] as String? ?? 'set';
      final val = action['value'];
      return 'Variable "$name" $op $val';
    case 'run_rule_actions':
      return 'Run rule: ${action['rule_id'] ?? ''}';
    case 'exit_rule':
      return 'Exit rule';
    case 'stop_rule_chain':
      return 'Stop rule chain';
    default:
      return type;
  }
}

// ─── Main page ────────────────────────────────────────────────────────────────

class AutomationEditorPage extends ConsumerStatefulWidget {
  final String? ruleId;
  const AutomationEditorPage({this.ruleId, super.key});

  @override
  ConsumerState<AutomationEditorPage> createState() =>
      _AutomationEditorPageState();
}

class _AutomationEditorPageState extends ConsumerState<AutomationEditorPage> {
  final _formKey = GlobalKey<FormState>();

  // Basic fields
  final _nameCtrl = TextEditingController();
  bool _enabled = true;

  // Trigger
  String _triggerType = 'device_state_changed';
  Map<String, dynamic> _trigger = {'type': 'device_state_changed'};

  // Conditions & Actions
  List<Map<String, dynamic>> _conditions = [];
  List<Map<String, dynamic>> _actions = [];

  // Settings
  final _priorityCtrl = TextEditingController(text: '0');
  String _runMode = 'parallel';
  int? _cooldownSecs;
  String _cooldownPreset = 'none';
  final _cooldownCustomCtrl = TextEditingController();
  List<String> _tags = [];
  final _tagCtrl = TextEditingController();

  bool _loading = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      if (widget.ruleId != null && widget.ruleId != 'new') {
        final rules = ref.read(automationsProvider).valueOrNull ?? [];
        final match = rules.where((r) => r.id == widget.ruleId).toList();
        if (match.isNotEmpty) _loadRule(match.first);
      }
    }
  }

  void _loadRule(HcRule rule) {
    _nameCtrl.text = rule.name;
    _enabled = rule.enabled;
    _priorityCtrl.text = rule.priority.toString();
    _runMode = rule.runMode.isNotEmpty ? rule.runMode : 'parallel';
    _trigger = Map<String, dynamic>.from(rule.trigger);
    _triggerType = rule.trigger['type'] as String? ?? 'device_state_changed';
    _conditions = rule.conditions.map((c) => Map<String, dynamic>.from(c)).toList();
    _actions = rule.actions.map((a) => Map<String, dynamic>.from(a)).toList();
    _tags = List<String>.from(rule.tags);

    // Cooldown preset
    final cs = rule.cooldownSecs;
    if (cs == null) {
      _cooldownPreset = 'none';
    } else if (cs == 30) {
      _cooldownPreset = '30s';
    } else if (cs == 60) {
      _cooldownPreset = '1m';
    } else if (cs == 300) {
      _cooldownPreset = '5m';
    } else {
      _cooldownPreset = 'custom';
      _cooldownCustomCtrl.text = cs.toString();
    }
    _cooldownSecs = cs;
  }

  int? _resolveCooldown() {
    switch (_cooldownPreset) {
      case 'none':
        return null;
      case '30s':
        return 30;
      case '1m':
        return 60;
      case '5m':
        return 300;
      case 'custom':
        return int.tryParse(_cooldownCustomCtrl.text);
      default:
        return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final cooldown = _resolveCooldown();
      final payload = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'enabled': _enabled,
        'priority': int.tryParse(_priorityCtrl.text) ?? 0,
        'run_mode': _runMode,
        'trigger': _trigger,
        'conditions': _conditions,
        'actions': _actions,
        'tags': _tags,
        if (cooldown != null) 'cooldown_secs': cooldown,
      };
      final api = ref.read(automationsApiProvider);
      if (widget.ruleId == null || widget.ruleId == 'new') {
        await api.createRule(payload);
      } else {
        await api.updateRule(widget.ruleId!, payload);
      }
      await ref.read(automationsProvider.notifier).reload();
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priorityCtrl.dispose();
    _cooldownCustomCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  // ─── Trigger type label ──────────────────────────────────────────────────

  static const _triggerLabels = {
    'device_state_changed': 'Device State Changed',
    'device_availability_changed': 'Device Availability Changed',
    'time_of_day': 'Time of Day',
    'sun_event': 'Sun Event',
    'mode_changed': 'Mode Changed',
    'webhook_received': 'Webhook Received',
    'manual_trigger': 'Manual Trigger',
    'mqtt_message': 'MQTT Message',
    'custom_event': 'Custom Event',
    'system_started': 'System Started',
    'cron': 'Cron Schedule',
    'periodic': 'Periodic',
    'button_event': 'Button Event',
    'numeric_threshold': 'Numeric Threshold',
    'hub_variable_changed': 'Hub Variable Changed',
    'calendar_event': 'Calendar Event',
  };

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dr = ref.watch(deviceNameResolverProvider);
    final mr = ref.watch(modeNameResolverProvider);
    final isNew = widget.ruleId == null || widget.ruleId == 'new';

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New Automation' : 'Edit Automation'),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Cancel'),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildNameCard(),
            const SizedBox(height: 12),
            _buildTriggerCard(dr, mr),
            const SizedBox(height: 12),
            _buildConditionsCard(dr, mr),
            const SizedBox(height: 12),
            _buildActionsCard(dr),
            const SizedBox(height: 12),
            _buildSettingsCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ─── Name card ───────────────────────────────────────────────────────────

  Widget _buildNameCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Rule Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Enabled',
                    style: Theme.of(context).textTheme.labelMedium),
                Switch(
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Trigger card ────────────────────────────────────────────────────────

  Widget _buildTriggerCard(DeviceNameResolver dr, ModeNameResolver mr) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Trigger', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _triggerType,
              decoration: const InputDecoration(
                labelText: 'Trigger Type',
                border: OutlineInputBorder(),
              ),
              items: _triggerLabels.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _triggerType = v;
                  _trigger = {'type': v};
                });
              },
            ),
            const SizedBox(height: 12),
            _TriggerForm(
              triggerType: _triggerType,
              trigger: _trigger,
              deviceResolver: dr,
              modeResolver: mr,
              onChanged: (updated) => setState(() => _trigger = updated),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Conditions card ─────────────────────────────────────────────────────

  Widget _buildConditionsCard(DeviceNameResolver dr, ModeNameResolver mr) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Conditions (AND)',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: () async {
                    final result = await showDialog<Map<String, dynamic>>(
                      context: context,
                      builder: (_) => _ConditionEditorDialog(
                        deviceResolver: dr,
                        modeResolver: mr,
                        initial: null,
                      ),
                    );
                    if (result != null) {
                      setState(() => _conditions.add(result));
                    }
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 16),
                      SizedBox(width: 4),
                      Text('Add Condition'),
                    ],
                  ),
                ),
              ],
            ),
            if (_conditions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No conditions — rule fires whenever trigger matches.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              )
            else
              ...List.generate(_conditions.length, (i) {
                final cond = _conditions[i];
                return Card(
                  margin: const EdgeInsets.only(top: 8),
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withOpacity(0.4),
                  child: ListTile(
                    leading: const Icon(Icons.filter_alt_outlined),
                    title: Text(_conditionSummary(cond, dr, mr)),
                    subtitle: Text(cond['type'] as String? ?? ''),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit',
                          onPressed: () async {
                            final result =
                                await showDialog<Map<String, dynamic>>(
                              context: context,
                              builder: (_) => _ConditionEditorDialog(
                                deviceResolver: dr,
                                modeResolver: mr,
                                initial: cond,
                              ),
                            );
                            if (result != null) {
                              setState(() => _conditions[i] = result);
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete',
                          onPressed: () =>
                              setState(() => _conditions.removeAt(i)),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ─── Actions card ────────────────────────────────────────────────────────

  Widget _buildActionsCard(DeviceNameResolver dr) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Actions',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: () async {
                    final result = await showDialog<Map<String, dynamic>>(
                      context: context,
                      builder: (_) => _ActionEditorDialog(
                        deviceResolver: dr,
                        modeResolver: ref.read(modeNameResolverProvider),
                        initial: null,
                      ),
                    );
                    if (result != null) {
                      setState(() => _actions.add(result));
                    }
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 16),
                      SizedBox(width: 4),
                      Text('Add Action'),
                    ],
                  ),
                ),
              ],
            ),
            if (_actions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No actions configured.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              )
            else
              ...List.generate(_actions.length, (i) {
                final action = _actions[i];
                return Card(
                  margin: const EdgeInsets.only(top: 8),
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withOpacity(0.4),
                  child: ListTile(
                    leading: const Icon(Icons.bolt_outlined),
                    title: Text(_actionSummary(action, dr)),
                    subtitle: Text(action['type'] as String? ?? ''),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit',
                          onPressed: () async {
                            final result =
                                await showDialog<Map<String, dynamic>>(
                              context: context,
                              builder: (_) => _ActionEditorDialog(
                                deviceResolver: dr,
                                modeResolver:
                                    ref.read(modeNameResolverProvider),
                                initial: action,
                              ),
                            );
                            if (result != null) {
                              setState(() => _actions[i] = result);
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete',
                          onPressed: () =>
                              setState(() => _actions.removeAt(i)),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ─── Settings card ───────────────────────────────────────────────────────

  Widget _buildSettingsCard() {
    return Card(
      child: ExpansionTile(
        title: const Text('Settings'),
        childrenPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Priority
          TextFormField(
            controller: _priorityCtrl,
            decoration: const InputDecoration(
              labelText: 'Priority',
              helperText: 'Higher priority rules run first (default 0)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),

          // Cooldown
          DropdownButtonFormField<String>(
            value: _cooldownPreset,
            decoration: const InputDecoration(
              labelText: 'Cooldown',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'none', child: Text('None')),
              DropdownMenuItem(value: '30s', child: Text('30 seconds')),
              DropdownMenuItem(value: '1m', child: Text('1 minute')),
              DropdownMenuItem(value: '5m', child: Text('5 minutes')),
              DropdownMenuItem(value: 'custom', child: Text('Custom...')),
            ],
            onChanged: (v) => setState(() {
              _cooldownPreset = v ?? 'none';
              _cooldownSecs = _resolveCooldown();
            }),
          ),
          if (_cooldownPreset == 'custom') ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _cooldownCustomCtrl,
              decoration: const InputDecoration(
                labelText: 'Cooldown (seconds)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {
                _cooldownSecs = _resolveCooldown();
              }),
            ),
          ],
          const SizedBox(height: 16),

          // Run mode
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Run Mode',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _runMode,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'parallel',
                      child: Text('Parallel — run multiple instances at once')),
                  DropdownMenuItem(
                      value: 'single',
                      child: Text('Single — skip if already running')),
                  DropdownMenuItem(
                      value: 'restart',
                      child: Text('Restart — cancel and restart')),
                  DropdownMenuItem(
                      value: 'queued',
                      child: Text('Queued — queue and run in order')),
                ],
                onChanged: (v) => setState(() => _runMode = v ?? 'parallel'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Tags
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tags', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              if (_tags.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: _tags
                      .map((tag) => Chip(
                            label: Text(tag),
                            onDeleted: () =>
                                setState(() => _tags.remove(tag)),
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tagCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Add tag',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (v) {
                        final tag = v.trim();
                        if (tag.isNotEmpty && !_tags.contains(tag)) {
                          setState(() {
                            _tags.add(tag);
                            _tagCtrl.clear();
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      final tag = _tagCtrl.text.trim();
                      if (tag.isNotEmpty && !_tags.contains(tag)) {
                        setState(() {
                          _tags.add(tag);
                          _tagCtrl.clear();
                        });
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Trigger form ─────────────────────────────────────────────────────────────

class _TriggerForm extends StatefulWidget {
  final String triggerType;
  final Map<String, dynamic> trigger;
  final DeviceNameResolver deviceResolver;
  final ModeNameResolver modeResolver;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const _TriggerForm({
    required this.triggerType,
    required this.trigger,
    required this.deviceResolver,
    required this.modeResolver,
    required this.onChanged,
  });

  @override
  State<_TriggerForm> createState() => _TriggerFormState();
}

class _TriggerFormState extends State<_TriggerForm> {
  late Map<String, dynamic> _data;
  // Separate slot list for device_state_changed — allows empty "pending" slots
  // that haven't been filled yet without corrupting _data.
  late List<String> _deviceSlots;

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.trigger);
    if (_data['type'] == null) _data['type'] = widget.triggerType;
    _deviceSlots = _slotsFromData();
  }

  @override
  void didUpdateWidget(_TriggerForm old) {
    super.didUpdateWidget(old);
    if (old.triggerType != widget.triggerType) {
      // Trigger type switched — reset everything.
      _data = {'type': widget.triggerType};
      _deviceSlots = [''];
    } else if (old.trigger != widget.trigger &&
        widget.trigger['type'] != _data['type']) {
      // External data reload (e.g. navigating to a different rule).
      _data = Map<String, dynamic>.from(widget.trigger);
      _deviceSlots = _slotsFromData();
    }
  }

  /// Build the initial slot list from _data.
  List<String> _slotsFromData() {
    final primary = _data['device_id'] as String? ?? '';
    final extra = (_data['device_ids'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final all = [if (primary.isNotEmpty) primary, ...extra];
    return all.isEmpty ? [''] : all;
  }

  /// Write _deviceSlots back to _data and notify parent.
  /// Empty slots are excluded from device_id / device_ids.
  void _flushDeviceSlots() {
    final nonEmpty = _deviceSlots.where((id) => id.isNotEmpty).toList();
    if (nonEmpty.isEmpty) {
      _data.remove('device_id');
      _data.remove('device_ids');
    } else {
      _data['device_id'] = nonEmpty.first;
      if (nonEmpty.length > 1) {
        _data['device_ids'] = nonEmpty.sublist(1);
      } else {
        _data.remove('device_ids');
      }
    }
    widget.onChanged(Map<String, dynamic>.from(_data));
  }

  void _set(String key, dynamic value) {
    setState(() {
      _data[key] = value;
      widget.onChanged(Map<String, dynamic>.from(_data));
    });
  }

  void _remove(String key) {
    setState(() {
      _data.remove(key);
      widget.onChanged(Map<String, dynamic>.from(_data));
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.triggerType) {
      case 'device_state_changed':
        return _buildDeviceStateChanged();
      case 'device_availability_changed':
        return _buildDeviceAvailabilityChanged();
      case 'time_of_day':
        return _buildTimeOfDay();
      case 'sun_event':
        return _buildSunEvent();
      case 'mode_changed':
        return _buildModeChanged();
      case 'webhook_received':
        return _buildWebhookReceived();
      case 'manual_trigger':
        return _buildManualTrigger();
      case 'mqtt_message':
        return _buildMqttMessage();
      case 'custom_event':
        return _buildCustomEvent();
      case 'system_started':
        return _buildSystemStarted();
      case 'cron':
        return _buildCron();
      case 'periodic':
        return _buildPeriodic();
      case 'button_event':
        return _buildButtonEvent();
      case 'numeric_threshold':
        return _buildNumericThreshold();
      case 'hub_variable_changed':
        return _buildHubVariableChanged();
      case 'calendar_event':
        return _buildCalendarEvent();
      default:
        return const Text('No configuration needed.');
    }
  }

  Widget _buildDeviceStateChanged() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One picker row per slot
        for (int i = 0; i < _deviceSlots.length; i++)
          Padding(
            key: ValueKey('device_slot_$i'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: _DevicePicker(
                    hint: i == 0 ? 'Device (required)' : 'Additional device',
                    value: _deviceSlots[i].isEmpty ? null : _deviceSlots[i],
                    devices: widget.deviceResolver.devices,
                    onChanged: (v) {
                      setState(() {
                        _deviceSlots[i] = v ?? '';
                        _flushDeviceSlots();
                      });
                    },
                  ),
                ),
                if (_deviceSlots.length > 1)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    tooltip: 'Remove device',
                    onPressed: () {
                      setState(() {
                        _deviceSlots.removeAt(i);
                        _flushDeviceSlots();
                      });
                    },
                  ),
              ],
            ),
          ),
        // Add device button — just appends an empty slot, no data flush yet
        TextButton.icon(
          onPressed: () => setState(() => _deviceSlots.add('')),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add device (OR)'),
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4)),
        ),
        const SizedBox(height: 8),
        _FormField(
          label: 'Attribute (optional)',
          value: _data['attribute'] as String? ?? '',
          onChanged: (v) =>
              v.isEmpty ? _remove('attribute') : _set('attribute', v),
        ),
        const SizedBox(height: 8),
        _FormField(
          label: 'To value (optional)',
          value: _data['to'] != null ? jsonEncode(_data['to']) : '',
          hint: 'e.g. true, 42, "open"',
          onChanged: (v) {
            if (v.isEmpty) {
              _remove('to');
            } else {
              try {
                _set('to', jsonDecode(v));
              } catch (_) {
                _set('to', v);
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildDeviceAvailabilityChanged() {
    final toVal = _data['to'];
    String toStr = 'any';
    if (toVal == true) toStr = 'online';
    if (toVal == false) toStr = 'offline';
    return Column(
      children: [
        _DevicePicker(
          hint: 'Select device',
          value: _data['device_id'] as String?,
          devices: widget.deviceResolver.devices,
          onChanged: (v) => _set('device_id', v),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: toStr,
          decoration: const InputDecoration(
            labelText: 'To state',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'any', child: Text('Any (online or offline)')),
            DropdownMenuItem(value: 'online', child: Text('Online')),
            DropdownMenuItem(value: 'offline', child: Text('Offline')),
          ],
          onChanged: (v) {
            if (v == 'any') _remove('to');
            if (v == 'online') _set('to', true);
            if (v == 'offline') _set('to', false);
          },
        ),
      ],
    );
  }

  Widget _buildTimeOfDay() {
    final days = List<String>.from(_data['days'] as List? ?? [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
    ]);
    const allDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormField(
          label: 'Time (HH:MM or HH:MM:SS)',
          value: _data['time'] as String? ?? '',
          hint: '07:30:00',
          onChanged: (v) => _set('time', v),
        ),
        const SizedBox(height: 12),
        Text('Days', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Row(
          children: [
            ActionChip(
              label: const Text('All'),
              onPressed: () => _set('days', List<String>.from(allDays)),
            ),
            const SizedBox(width: 4),
            ActionChip(
              label: const Text('Weekdays'),
              onPressed: () =>
                  _set('days', ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']),
            ),
            const SizedBox(width: 4),
            ActionChip(
              label: const Text('Weekend'),
              onPressed: () => _set('days', ['Sat', 'Sun']),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: allDays.map((d) {
            final selected = days.contains(d);
            return FilterChip(
              label: Text(d),
              selected: selected,
              onSelected: (on) {
                final updated = List<String>.from(days);
                if (on) {
                  updated.add(d);
                } else {
                  updated.remove(d);
                }
                // Preserve order
                updated.sort((a, b) =>
                    allDays.indexOf(a).compareTo(allDays.indexOf(b)));
                _set('days', updated);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSunEvent() {
    final offset = (_data['offset_minutes'] as num?)?.toInt() ?? 0;
    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: _data['event'] as String? ?? 'sunset',
          decoration: const InputDecoration(
            labelText: 'Solar event',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'sunrise', child: Text('Sunrise')),
            DropdownMenuItem(value: 'sunset', child: Text('Sunset')),
            DropdownMenuItem(value: 'solar_noon', child: Text('Solar Noon')),
            DropdownMenuItem(value: 'civil_dawn', child: Text('Civil Dawn')),
            DropdownMenuItem(value: 'civil_dusk', child: Text('Civil Dusk')),
          ],
          onChanged: (v) => _set('event', v ?? 'sunset'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Offset: ${offset > 0 ? '+' : ''}${offset} min',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Slider(
                    value: offset.toDouble(),
                    min: -120,
                    max: 120,
                    divisions: 48,
                    label: '${offset > 0 ? '+' : ''}${offset} min',
                    onChanged: (v) => _set('offset_minutes', v.round()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModeChanged() {
    final toVal = _data['to'];
    String toStr = 'any';
    if (toVal == true) toStr = 'on';
    if (toVal == false) toStr = 'off';
    return Column(
      children: [
        _ModePicker(
          value: _data['mode_id'] as String?,
          modes: widget.modeResolver.modes,
          nullable: true,
          nullLabel: 'Any mode',
          onChanged: (v) {
            if (v == null) {
              _remove('mode_id');
            } else {
              _set('mode_id', v);
            }
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: toStr,
          decoration: const InputDecoration(
            labelText: 'To state',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'any', child: Text('Any (on or off)')),
            DropdownMenuItem(value: 'on', child: Text('On')),
            DropdownMenuItem(value: 'off', child: Text('Off')),
          ],
          onChanged: (v) {
            if (v == 'any') _remove('to');
            if (v == 'on') _set('to', true);
            if (v == 'off') _set('to', false);
          },
        ),
      ],
    );
  }

  Widget _buildWebhookReceived() {
    return _FormField(
      label: 'Path',
      value: _data['path'] as String? ?? '',
      hint: '/webhook/my-hook',
      onChanged: (v) => _set('path', v),
    );
  }

  Widget _buildManualTrigger() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'This rule can only be triggered manually via the API or dashboard.',
        style: TextStyle(fontStyle: FontStyle.italic),
      ),
    );
  }

  Widget _buildMqttMessage() {
    return Column(
      children: [
        _FormField(
          label: 'Topic pattern',
          value: _data['topic_pattern'] as String? ?? '',
          hint: 'homecore/+/state',
          onChanged: (v) => _set('topic_pattern', v),
        ),
        const SizedBox(height: 8),
        _FormField(
          label: 'Payload match (optional)',
          value: _data['payload'] as String? ?? '',
          onChanged: (v) => v.isEmpty ? _remove('payload') : _set('payload', v),
        ),
      ],
    );
  }

  Widget _buildCustomEvent() {
    return _FormField(
      label: 'Event type',
      value: _data['event_type'] as String? ?? '',
      hint: 'my_custom_event',
      onChanged: (v) => _set('event_type', v),
    );
  }

  Widget _buildSystemStarted() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'This rule fires once each time the homeCore system starts.',
        style: TextStyle(fontStyle: FontStyle.italic),
      ),
    );
  }

  Widget _buildCron() {
    return _FormField(
      label: 'Cron expression',
      value: _data['expression'] as String? ?? '',
      hint: '0 30 7 * * * (sec min hour day month weekday)',
      onChanged: (v) => _set('expression', v),
    );
  }

  Widget _buildPeriodic() {
    return Column(
      children: [
        _FormField(
          label: 'Every N',
          value: (_data['every_n'] as num?)?.toString() ?? '5',
          keyboardType: TextInputType.number,
          onChanged: (v) => _set('every_n', int.tryParse(v) ?? 5),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _data['unit'] as String? ?? 'minutes',
          decoration: const InputDecoration(
            labelText: 'Unit',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'minutes', child: Text('Minutes')),
            DropdownMenuItem(value: 'hours', child: Text('Hours')),
            DropdownMenuItem(value: 'days', child: Text('Days')),
            DropdownMenuItem(value: 'weeks', child: Text('Weeks')),
          ],
          onChanged: (v) => _set('unit', v ?? 'minutes'),
        ),
      ],
    );
  }

  Widget _buildButtonEvent() {
    return Column(
      children: [
        _DevicePicker(
          hint: 'Select button device',
          value: _data['device_id'] as String?,
          devices: widget.deviceResolver.devices,
          onChanged: (v) => _set('device_id', v),
        ),
        const SizedBox(height: 8),
        _FormField(
          label: 'Button number (optional)',
          value: (_data['button_number'] as num?)?.toString() ?? '',
          hint: 'e.g. 1',
          keyboardType: TextInputType.number,
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n == null) _remove('button_number');
            else _set('button_number', n);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _data['event'] as String? ?? 'pushed',
          decoration: const InputDecoration(
            labelText: 'Button event',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'pushed', child: Text('Pushed')),
            DropdownMenuItem(value: 'held', child: Text('Held')),
            DropdownMenuItem(value: 'double_tapped', child: Text('Double Tapped')),
            DropdownMenuItem(value: 'released', child: Text('Released')),
          ],
          onChanged: (v) => _set('event', v ?? 'pushed'),
        ),
      ],
    );
  }

  Widget _buildNumericThreshold() {
    return Column(
      children: [
        _DevicePicker(
          hint: 'Select device',
          value: _data['device_id'] as String?,
          devices: widget.deviceResolver.devices,
          onChanged: (v) => _set('device_id', v),
        ),
        const SizedBox(height: 8),
        _FormField(
          label: 'Attribute',
          value: _data['attribute'] as String? ?? '',
          hint: 'e.g. temperature',
          onChanged: (v) => _set('attribute', v),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _data['op'] as String? ?? 'above',
          decoration: const InputDecoration(
            labelText: 'Operator',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'above', child: Text('Above')),
            DropdownMenuItem(value: 'below', child: Text('Below')),
            DropdownMenuItem(value: 'crosses_above', child: Text('Crosses Above')),
            DropdownMenuItem(value: 'crosses_below', child: Text('Crosses Below')),
          ],
          onChanged: (v) => _set('op', v ?? 'above'),
        ),
        const SizedBox(height: 8),
        _FormField(
          label: 'Value',
          value: (_data['value'] as num?)?.toString() ?? '',
          keyboardType: TextInputType.number,
          onChanged: (v) => _set('value', num.tryParse(v) ?? 0),
        ),
      ],
    );
  }

  Widget _buildHubVariableChanged() {
    return _FormField(
      label: 'Variable name (optional)',
      value: _data['name'] as String? ?? '',
      hint: 'Leave blank to match any variable',
      onChanged: (v) => v.isEmpty ? _remove('name') : _set('name', v),
    );
  }

  Widget _buildCalendarEvent() {
    return Column(
      children: [
        _FormField(
          label: 'Calendar ID (optional)',
          value: _data['calendar_id'] as String? ?? '',
          onChanged: (v) => v.isEmpty ? _remove('calendar_id') : _set('calendar_id', v),
        ),
        const SizedBox(height: 8),
        _FormField(
          label: 'Title contains (optional)',
          value: _data['title_contains'] as String? ?? '',
          hint: 'e.g. "Meeting"',
          onChanged: (v) =>
              v.isEmpty ? _remove('title_contains') : _set('title_contains', v),
        ),
        const SizedBox(height: 8),
        _FormField(
          label: 'Offset minutes (optional)',
          value: (_data['offset_minutes'] as num?)?.toString() ?? '',
          keyboardType: TextInputType.number,
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n == null) _remove('offset_minutes');
            else _set('offset_minutes', n);
          },
        ),
      ],
    );
  }
}

// ─── Condition editor dialog ──────────────────────────────────────────────────

class _ConditionEditorDialog extends StatefulWidget {
  final DeviceNameResolver deviceResolver;
  final ModeNameResolver modeResolver;
  final Map<String, dynamic>? initial;

  const _ConditionEditorDialog({
    required this.deviceResolver,
    required this.modeResolver,
    required this.initial,
  });

  @override
  State<_ConditionEditorDialog> createState() => _ConditionEditorDialogState();
}

class _ConditionEditorDialogState extends State<_ConditionEditorDialog> {
  late String _type;
  late Map<String, dynamic> _data;
  final _jsonCtrl = TextEditingController();

  static const _conditionTypes = [
    'device_state',
    'mode_is',
    'time_window',
    'time_elapsed',
    'hub_variable',
    'script_expression',
    'private_boolean_is',
    'not',
    'and',
    'or',
    'xor',
  ];

  static const _conditionLabels = {
    'device_state': 'Device State',
    'mode_is': 'Mode Is',
    'time_window': 'Time Window',
    'time_elapsed': 'Time Elapsed (unchanged)',
    'hub_variable': 'Hub Variable',
    'script_expression': 'Script Expression',
    'private_boolean_is': 'Private Boolean',
    'not': 'NOT (negate condition)',
    'and': 'AND (all must pass)',
    'or': 'OR (any must pass)',
    'xor': 'XOR (exactly one must pass)',
  };

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _data = Map<String, dynamic>.from(widget.initial!);
      _type = _data['type'] as String? ?? 'device_state';
    } else {
      _type = 'device_state';
      _data = {'type': _type};
    }
    final isKnown = _conditionTypes.contains(_type);
    if (!isKnown) {
      _jsonCtrl.text =
          const JsonEncoder.withIndent('  ').convert(_data);
    }
  }

  @override
  void dispose() {
    _jsonCtrl.dispose();
    super.dispose();
  }

  void _set(String key, dynamic value) {
    setState(() => _data[key] = value);
  }

  void _remove(String key) {
    setState(() => _data.remove(key));
  }

  static const _jsonEditorTypes = {'not', 'and', 'or', 'xor'};

  Map<String, dynamic>? _build() {
    final isKnown = _conditionTypes.contains(_type);
    // not/and/or/xor are "known" types but edited via JSON controller
    if (!isKnown || _jsonEditorTypes.contains(_type)) {
      try {
        return Map<String, dynamic>.from(jsonDecode(_jsonCtrl.text) as Map);
      } catch (_) {
        return null;
      }
    }
    return Map<String, dynamic>.from(_data);
  }

  @override
  Widget build(BuildContext context) {
    final isKnown = _conditionTypes.contains(_type);
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add Condition' : 'Edit Condition'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: isKnown ? _type : null,
                hint: isKnown ? null : Text(_type),
                decoration: const InputDecoration(
                  labelText: 'Condition type',
                  border: OutlineInputBorder(),
                ),
                items: [
                  ..._conditionTypes.map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(_conditionLabels[t] ?? t),
                      )),
                  if (!isKnown)
                    DropdownMenuItem(
                      value: _type,
                      child: Text(_type),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _type = v;
                    _data = {'type': v};
                    if (!_conditionTypes.contains(v)) {
                      _jsonCtrl.text =
                          const JsonEncoder.withIndent('  ').convert(_data);
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              if (isKnown)
                _buildKnownConditionForm()
              else
                _buildJsonForm(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final result = _build();
            Navigator.of(context).pop(result);
          },
          child: const Text('OK'),
        ),
      ],
    );
  }

  Widget _buildKnownConditionForm() {
    switch (_type) {
      case 'device_state':
        return Column(
          children: [
            _DevicePicker(
              hint: 'Select device',
              value: _data['device_id'] as String?,
              devices: widget.deviceResolver.devices,
              onChanged: (v) => _set('device_id', v),
            ),
            const SizedBox(height: 8),
            _FormField(
              label: 'Attribute',
              value: _data['attribute'] as String? ?? '',
              hint: 'e.g. on, temperature',
              onChanged: (v) => _set('attribute', v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _data['op'] as String? ?? 'eq',
              decoration: const InputDecoration(
                labelText: 'Operator',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'eq', child: Text('eq — equals')),
                DropdownMenuItem(value: 'ne', child: Text('ne — not equals')),
                DropdownMenuItem(value: 'gt', child: Text('gt — greater than')),
                DropdownMenuItem(value: 'gte', child: Text('gte — ≥')),
                DropdownMenuItem(value: 'lt', child: Text('lt — less than')),
                DropdownMenuItem(value: 'lte', child: Text('lte — ≤')),
              ],
              onChanged: (v) => _set('op', v ?? 'eq'),
            ),
            const SizedBox(height: 8),
            _FormField(
              label: 'Value',
              value: _data['value'] != null ? jsonEncode(_data['value']) : '',
              hint: 'e.g. true, 42, "open"',
              onChanged: (v) {
                try {
                  _set('value', jsonDecode(v));
                } catch (_) {
                  _set('value', v);
                }
              },
            ),
          ],
        );

      case 'mode_is':
        return Column(
          children: [
            _ModePicker(
              value: _data['mode_id'] as String?,
              modes: widget.modeResolver.modes,
              nullable: false,
              nullLabel: '',
              onChanged: (v) {
                if (v != null) _set('mode_id', v);
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Mode is on'),
              value: _data['on'] as bool? ?? true,
              onChanged: (v) => _set('on', v),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        );

      case 'time_window':
        return Column(
          children: [
            _FormField(
              label: 'Start time (HH:MM or HH:MM:SS)',
              value: _data['start'] as String? ?? '',
              hint: '08:00:00',
              onChanged: (v) => _set('start', v),
            ),
            const SizedBox(height: 8),
            _FormField(
              label: 'End time (HH:MM or HH:MM:SS)',
              value: _data['end'] as String? ?? '',
              hint: '22:00:00',
              onChanged: (v) => _set('end', v),
            ),
          ],
        );

      case 'hub_variable':
        return Column(
          children: [
            _FormField(
              label: 'Variable name',
              value: _data['name'] as String? ?? '',
              onChanged: (v) => _set('name', v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _data['op'] as String? ?? 'eq',
              decoration: const InputDecoration(
                labelText: 'Operator',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'eq', child: Text('eq — equals')),
                DropdownMenuItem(value: 'ne', child: Text('ne — not equals')),
                DropdownMenuItem(value: 'gt', child: Text('gt — greater than')),
                DropdownMenuItem(value: 'gte', child: Text('gte — ≥')),
                DropdownMenuItem(value: 'lt', child: Text('lt — less than')),
                DropdownMenuItem(value: 'lte', child: Text('lte — ≤')),
              ],
              onChanged: (v) => _set('op', v ?? 'eq'),
            ),
            const SizedBox(height: 8),
            _FormField(
              label: 'Value',
              value: _data['value'] != null ? jsonEncode(_data['value']) : '',
              hint: 'e.g. true, 42, "hello"',
              onChanged: (v) {
                try {
                  _set('value', jsonDecode(v));
                } catch (_) {
                  _set('value', v);
                }
              },
            ),
          ],
        );

      case 'time_elapsed':
        return Column(
          children: [
            _DevicePicker(
              hint: 'Select device',
              value: _data['device_id'] as String?,
              devices: widget.deviceResolver.devices,
              onChanged: (v) => _set('device_id', v),
            ),
            const SizedBox(height: 8),
            _FormField(
              label: 'Attribute',
              value: _data['attribute'] as String? ?? '',
              hint: 'e.g. on, motion',
              onChanged: (v) => _set('attribute', v),
            ),
            const SizedBox(height: 8),
            _FormField(
              label: 'Duration (seconds)',
              value: (_data['duration_secs'] as num?)?.toString() ?? '',
              hint: 'e.g. 300 (5 minutes)',
              keyboardType: TextInputType.number,
              onChanged: (v) =>
                  _set('duration_secs', int.tryParse(v) ?? 0),
            ),
          ],
        );

      case 'script_expression':
        return TextFormField(
          initialValue: _data['script'] as String? ?? '',
          decoration: const InputDecoration(
            labelText: 'Script',
            border: OutlineInputBorder(),
            helperText: 'Rhai expression returning a boolean',
          ),
          maxLines: 5,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          onChanged: (v) => _set('script', v),
        );

      case 'private_boolean_is':
        return Column(
          children: [
            _FormField(
              label: 'Boolean name',
              value: _data['name'] as String? ?? '',
              hint: 'e.g. my_flag',
              onChanged: (v) => _set('name', v),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Expected value'),
              value: _data['value'] as bool? ?? true,
              onChanged: (v) => _set('value', v),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        );

      case 'not':
        _jsonCtrl.text = const JsonEncoder.withIndent('  ').convert(_data);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Wraps a single condition and inverts its result. '
              'Edit the nested condition as JSON:',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            ),
            const SizedBox(height: 8),
            _buildJsonForm(),
          ],
        );

      case 'and':
      case 'or':
      case 'xor':
        _jsonCtrl.text = const JsonEncoder.withIndent('  ').convert(_data);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_type.toUpperCase()} group — edit the nested conditions list as JSON:',
              style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            ),
            const SizedBox(height: 8),
            _buildJsonForm(),
          ],
        );

      default:
        return _buildJsonForm();
    }
  }

  Widget _buildJsonForm() {
    return TextFormField(
      controller: _jsonCtrl,
      maxLines: 10,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        labelText: 'Raw JSON',
        helperText: 'Edit condition as raw JSON',
      ),
    );
  }
}

// ─── Action editor dialog ─────────────────────────────────────────────────────

class _ActionEditorDialog extends StatefulWidget {
  final DeviceNameResolver deviceResolver;
  final ModeNameResolver modeResolver;
  final Map<String, dynamic>? initial;

  const _ActionEditorDialog({
    required this.deviceResolver,
    required this.modeResolver,
    required this.initial,
  });

  @override
  State<_ActionEditorDialog> createState() => _ActionEditorDialogState();
}

class _ActionEditorDialogState extends State<_ActionEditorDialog> {
  late String _type;
  late Map<String, dynamic> _data;
  final _jsonCtrl = TextEditingController();

  static const _actionTypes = [
    'set_device_state',
    'delay',
    'notify',
    'log_message',
    'fire_event',
    'comment',
    'set_mode',
    'set_hub_variable',
    'run_rule_actions',
    'exit_rule',
    'stop_rule_chain',
  ];

  static const _actionLabels = {
    'set_device_state': 'Set Device State',
    'delay': 'Delay',
    'notify': 'Notify',
    'log_message': 'Log Message',
    'fire_event': 'Fire Event',
    'comment': 'Comment',
    'set_mode': 'Set Mode',
    'set_hub_variable': 'Set Hub Variable',
    'run_rule_actions': 'Run Rule Actions',
    'exit_rule': 'Exit Rule',
    'stop_rule_chain': 'Stop Rule Chain',
  };

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _data = Map<String, dynamic>.from(widget.initial!);
      _type = _data['type'] as String? ?? 'set_device_state';
    } else {
      _type = 'set_device_state';
      _data = {'type': _type};
    }
    if (!_actionTypes.contains(_type)) {
      _jsonCtrl.text = const JsonEncoder.withIndent('  ').convert(_data);
    }
  }

  @override
  void dispose() {
    _jsonCtrl.dispose();
    super.dispose();
  }

  void _set(String key, dynamic value) {
    setState(() => _data[key] = value);
  }

  void _remove(String key) {
    setState(() => _data.remove(key));
  }

  Map<String, dynamic>? _build() {
    if (!_actionTypes.contains(_type)) {
      try {
        return Map<String, dynamic>.from(jsonDecode(_jsonCtrl.text) as Map);
      } catch (_) {
        return null;
      }
    }
    return Map<String, dynamic>.from(_data);
  }

  @override
  Widget build(BuildContext context) {
    final isKnown = _actionTypes.contains(_type);
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add Action' : 'Edit Action'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: isKnown ? _type : null,
                hint: isKnown ? null : Text(_type),
                decoration: const InputDecoration(
                  labelText: 'Action type',
                  border: OutlineInputBorder(),
                ),
                items: [
                  ..._actionTypes.map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(_actionLabels[t] ?? t),
                      )),
                  if (!isKnown)
                    DropdownMenuItem(
                      value: _type,
                      child: Text(_type),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _type = v;
                    _data = {'type': v};
                    if (!_actionTypes.contains(v)) {
                      _jsonCtrl.text =
                          const JsonEncoder.withIndent('  ').convert(_data);
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              if (isKnown)
                _buildKnownActionForm()
              else
                _buildJsonForm(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final result = _build();
            Navigator.of(context).pop(result);
          },
          child: const Text('OK'),
        ),
      ],
    );
  }

  Widget _buildKnownActionForm() {
    switch (_type) {
      case 'set_device_state':
        return Column(
          children: [
            _DevicePicker(
              hint: 'Select device',
              value: _data['device_id'] as String?,
              devices: widget.deviceResolver.devices,
              onChanged: (v) => _set('device_id', v),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _data['state'] != null
                  ? const JsonEncoder.withIndent('  ').convert(_data['state'])
                  : '{\n  "on": true\n}',
              decoration: const InputDecoration(
                labelText: 'State (JSON)',
                border: OutlineInputBorder(),
                helperText: 'e.g. {"on": true} or {"brightness": 80}',
              ),
              maxLines: 5,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              onChanged: (v) {
                try {
                  _set('state', jsonDecode(v));
                } catch (_) {}
              },
            ),
          ],
        );

      case 'delay':
        return Column(
          children: [
            _FormField(
              label: 'Duration (seconds)',
              value: (_data['duration_secs'] as num?)?.toString() ?? '',
              keyboardType: TextInputType.number,
              onChanged: (v) => _set('duration_secs', num.tryParse(v) ?? 0),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Cancelable'),
              value: _data['cancelable'] as bool? ?? false,
              onChanged: (v) => _set('cancelable', v),
              contentPadding: EdgeInsets.zero,
            ),
            if (_data['cancelable'] == true) ...[
              const SizedBox(height: 8),
              _FormField(
                label: 'Cancel key (optional)',
                value: _data['cancel_key'] as String? ?? '',
                hint: 'Unique key to cancel this delay',
                onChanged: (v) =>
                    v.isEmpty ? _remove('cancel_key') : _set('cancel_key', v),
              ),
            ],
          ],
        );

      case 'notify':
        return Column(
          children: [
            _FormField(
              label: 'Channel',
              value: _data['channel'] as String? ?? '',
              hint: 'e.g. pushover, slack',
              onChanged: (v) => _set('channel', v),
            ),
            const SizedBox(height: 8),
            _FormField(
              label: 'Message',
              value: _data['message'] as String? ?? '',
              onChanged: (v) => _set('message', v),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            _FormField(
              label: 'Title (optional)',
              value: _data['title'] as String? ?? '',
              onChanged: (v) =>
                  v.isEmpty ? _remove('title') : _set('title', v),
            ),
          ],
        );

      case 'log_message':
        return Column(
          children: [
            _FormField(
              label: 'Message',
              value: _data['message'] as String? ?? '',
              onChanged: (v) => _set('message', v),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _data['level'] as String? ?? 'info',
              decoration: const InputDecoration(
                labelText: 'Log level',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'trace', child: Text('Trace')),
                DropdownMenuItem(value: 'debug', child: Text('Debug')),
                DropdownMenuItem(value: 'info', child: Text('Info')),
                DropdownMenuItem(value: 'warn', child: Text('Warn')),
                DropdownMenuItem(value: 'error', child: Text('Error')),
              ],
              onChanged: (v) => _set('level', v ?? 'info'),
            ),
          ],
        );

      case 'fire_event':
        return Column(
          children: [
            _FormField(
              label: 'Event type',
              value: _data['event_type'] as String? ?? '',
              hint: 'e.g. my_custom_event',
              onChanged: (v) => _set('event_type', v),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _data['payload'] != null
                  ? const JsonEncoder.withIndent('  ').convert(_data['payload'])
                  : '{}',
              decoration: const InputDecoration(
                labelText: 'Payload (JSON)',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              onChanged: (v) {
                try {
                  _set('payload', jsonDecode(v));
                } catch (_) {}
              },
            ),
          ],
        );

      case 'comment':
        return _FormField(
          label: 'Comment text',
          value: _data['text'] as String? ?? '',
          onChanged: (v) => _set('text', v),
          maxLines: 3,
        );

      case 'set_mode':
        return Column(
          children: [
            _ModePicker(
              value: _data['mode_id'] as String?,
              modes: widget.modeResolver.modes,
              nullable: false,
              nullLabel: '',
              onChanged: (v) {
                if (v != null) _set('mode_id', v);
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _data['command'] as String? ?? 'on',
              decoration: const InputDecoration(
                labelText: 'Command',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'on', child: Text('On')),
                DropdownMenuItem(value: 'off', child: Text('Off')),
                DropdownMenuItem(value: 'toggle', child: Text('Toggle')),
              ],
              onChanged: (v) => _set('command', v ?? 'on'),
            ),
          ],
        );

      case 'set_hub_variable':
        return Column(
          children: [
            _FormField(
              label: 'Variable name',
              value: _data['name'] as String? ?? '',
              onChanged: (v) => _set('name', v),
            ),
            const SizedBox(height: 8),
            _FormField(
              label: 'Value',
              value: _data['value'] != null ? jsonEncode(_data['value']) : '',
              hint: 'e.g. true, 42, "hello"',
              onChanged: (v) {
                try {
                  _set('value', jsonDecode(v));
                } catch (_) {
                  _set('value', v);
                }
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _data['op'] as String? ?? 'set',
              decoration: const InputDecoration(
                labelText: 'Operation',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'set', child: Text('Set')),
                DropdownMenuItem(value: 'add', child: Text('Add')),
                DropdownMenuItem(value: 'subtract', child: Text('Subtract')),
                DropdownMenuItem(value: 'toggle', child: Text('Toggle')),
                DropdownMenuItem(value: 'multiply', child: Text('Multiply')),
                DropdownMenuItem(value: 'divide', child: Text('Divide')),
              ],
              onChanged: (v) => _set('op', v ?? 'set'),
            ),
          ],
        );

      case 'run_rule_actions':
        return _FormField(
          label: 'Rule ID (UUID)',
          value: _data['rule_id'] as String? ?? '',
          hint: 'The UUID of the rule whose actions to run',
          onChanged: (v) => _set('rule_id', v),
        );

      case 'exit_rule':
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Exits the current rule immediately. Subsequent actions in this rule will not run.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        );

      case 'stop_rule_chain':
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Stops the entire rule chain. No further rules will be evaluated for this event.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        );

      default:
        return _buildJsonForm();
    }
  }

  Widget _buildJsonForm() {
    return TextFormField(
      controller: _jsonCtrl,
      maxLines: 10,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        labelText: 'Raw JSON',
        helperText: 'Edit action as raw JSON',
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

/// A text form field with an outline border, suitable for trigger/condition/action forms.
class _FormField extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final TextInputType keyboardType;
  final int maxLines;
  final ValueChanged<String> onChanged;

  const _FormField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
    );
  }
}

/// Device picker dropdown grouped visually by area.
class _DevicePicker extends StatelessWidget {
  final String hint;
  final String? value;
  final List<DeviceState> devices;
  final ValueChanged<String?> onChanged;

  const _DevicePicker({
    required this.hint,
    required this.value,
    required this.devices,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Build area-grouped list: sort by area then name
    final sorted = List<DeviceState>.from(devices)
      ..sort((a, b) {
        final aArea = a.area ?? '';
        final bArea = b.area ?? '';
        final cmp = aArea.compareTo(bArea);
        return cmp != 0 ? cmp : a.displayName.compareTo(b.displayName);
      });

    // Check if current value exists in device list; if not, add a synthetic entry
    final knownIds = sorted.map((d) => d.id).toSet();
    final effectiveValue =
        (value != null && value!.isNotEmpty) ? value : null;

    final items = <DropdownMenuItem<String>>[];
    String? lastArea;
    for (final device in sorted) {
      final area = device.area ?? 'No Area';
      if (area != lastArea) {
        // Area header (disabled item used as visual separator)
        items.add(DropdownMenuItem<String>(
          enabled: false,
          value: '__header_$area',
          child: Text(
            area.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ));
        lastArea = area;
      }
      items.add(DropdownMenuItem<String>(
        value: device.id,
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(device.displayName),
        ),
      ));
    }

    // If current value isn't in the list, add it at the top
    if (effectiveValue != null && !knownIds.contains(effectiveValue)) {
      items.insert(
        0,
        DropdownMenuItem<String>(
          value: effectiveValue,
          child: Text(effectiveValue),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      value: effectiveValue,
      hint: Text(hint),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: hint,
        border: const OutlineInputBorder(),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

/// Mode picker dropdown.
class _ModePicker extends StatelessWidget {
  final String? value;
  final List<ModeState> modes;
  final bool nullable;
  final String nullLabel;
  final ValueChanged<String?> onChanged;

  const _ModePicker({
    required this.value,
    required this.modes,
    required this.nullable,
    required this.nullLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String>>[];
    if (nullable) {
      items.add(DropdownMenuItem<String>(
        value: null,
        child: Text(nullLabel.isEmpty ? '— any —' : nullLabel),
      ));
    }
    for (final mode in modes) {
      items.add(DropdownMenuItem<String>(
        value: mode.id,
        child: Text(mode.displayName),
      ));
    }
    return DropdownButtonFormField<String>(
      value: value,
      decoration: const InputDecoration(
        labelText: 'Mode',
        border: OutlineInputBorder(),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}
