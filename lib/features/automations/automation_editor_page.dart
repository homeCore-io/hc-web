import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/automations_provider.dart';

class AutomationEditorPage extends ConsumerStatefulWidget {
  final String? ruleId;
  const AutomationEditorPage({this.ruleId, super.key});

  @override
  ConsumerState<AutomationEditorPage> createState() =>
      _AutomationEditorPageState();
}

class _AutomationEditorPageState extends ConsumerState<AutomationEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _priorityCtrl = TextEditingController(text: '0');
  bool _enabled = true;

  // Trigger state
  String _triggerType = 'device_state_changed';
  final Map<String, TextEditingController> _triggerCtrls = {};

  // Conditions — each is a Map<String, dynamic> being edited as JSON text
  final List<TextEditingController> _conditionCtrls = [];

  // Actions — each is a Map<String, dynamic> being edited as JSON text
  final List<TextEditingController> _actionCtrls = [];

  bool _loading = false;
  bool _initialized = false;

  static const _triggerTypes = [
    'device_state_changed',
    'time_of_day',
    'sun_event',
    'webhook_received',
    'manual_trigger',
    'mqtt_message',
  ];

  @override
  void initState() {
    super.initState();
    _triggerCtrls['device_id'] = TextEditingController();
    _triggerCtrls['attribute'] = TextEditingController();
    _triggerCtrls['to'] = TextEditingController();
    _triggerCtrls['time'] = TextEditingController();
    _triggerCtrls['days'] =
        TextEditingController(text: 'Mon,Tue,Wed,Thu,Fri,Sat,Sun');
    _triggerCtrls['event'] = TextEditingController(text: 'sunset');
    _triggerCtrls['offset_minutes'] = TextEditingController(text: '0');
    _triggerCtrls['path'] = TextEditingController();
    _triggerCtrls['topic_pattern'] = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized && widget.ruleId != null && widget.ruleId != 'new') {
      _initialized = true;
      final rules = ref.read(automationsProvider).valueOrNull ?? [];
      final matching = rules.where((r) => r.id == widget.ruleId).toList();
      if (matching.isNotEmpty) {
        final rule = matching.first;
        _nameCtrl.text = rule.name;
        _priorityCtrl.text = rule.priority.toString();
        _enabled = rule.enabled;
        _loadTrigger(rule.trigger);
        for (final c in rule.conditions) {
          _conditionCtrls.add(TextEditingController(
              text: const JsonEncoder.withIndent('  ').convert(c)));
        }
        for (final a in rule.actions) {
          _actionCtrls.add(TextEditingController(
              text: const JsonEncoder.withIndent('  ').convert(a)));
        }
      }
    } else if (!_initialized) {
      _initialized = true;
    }
  }

  void _loadTrigger(Map<String, dynamic> t) {
    _triggerType = t['type'] as String? ?? 'device_state_changed';
    _triggerCtrls['device_id']!.text = t['device_id'] as String? ?? '';
    _triggerCtrls['attribute']!.text = t['attribute'] as String? ?? '';
    _triggerCtrls['to']!.text =
        t['to'] != null ? jsonEncode(t['to']) : '';
    _triggerCtrls['time']!.text = t['time'] as String? ?? '';
    _triggerCtrls['days']!.text =
        (t['days'] as List?)?.join(',') ?? '';
    _triggerCtrls['event']!.text = t['event'] as String? ?? 'sunset';
    _triggerCtrls['offset_minutes']!.text =
        (t['offset_minutes'] as int?)?.toString() ?? '0';
    _triggerCtrls['path']!.text = t['path'] as String? ?? '';
    _triggerCtrls['topic_pattern']!.text =
        t['topic_pattern'] as String? ?? '';
  }

  Map<String, dynamic> _buildTrigger() {
    final t = <String, dynamic>{'type': _triggerType};
    switch (_triggerType) {
      case 'device_state_changed':
        t['device_id'] = _triggerCtrls['device_id']!.text;
        if (_triggerCtrls['attribute']!.text.isNotEmpty) {
          t['attribute'] = _triggerCtrls['attribute']!.text;
        }
        if (_triggerCtrls['to']!.text.isNotEmpty) {
          try {
            t['to'] = jsonDecode(_triggerCtrls['to']!.text);
          } catch (_) {}
        }
      case 'time_of_day':
        t['time'] = _triggerCtrls['time']!.text;
        t['days'] = _triggerCtrls['days']!
            .text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      case 'sun_event':
        t['event'] = _triggerCtrls['event']!.text;
        t['offset_minutes'] =
            int.tryParse(_triggerCtrls['offset_minutes']!.text) ?? 0;
      case 'webhook_received':
        t['path'] = _triggerCtrls['path']!.text;
      case 'mqtt_message':
        t['topic_pattern'] = _triggerCtrls['topic_pattern']!.text;
    }
    return t;
  }

  List<Map<String, dynamic>> _parseJsonList(
      List<TextEditingController> ctrls) {
    final result = <Map<String, dynamic>>[];
    for (final c in ctrls) {
      try {
        result.add(Map<String, dynamic>.from(jsonDecode(c.text) as Map));
      } catch (_) {}
    }
    return result;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final payload = {
        'name': _nameCtrl.text,
        'enabled': _enabled,
        'priority': int.tryParse(_priorityCtrl.text) ?? 0,
        'trigger': _buildTrigger(),
        'conditions': _parseJsonList(_conditionCtrls),
        'actions': _parseJsonList(_actionCtrls),
      };
      final api = ref.read(automationsApiProvider);
      if (widget.ruleId == null || widget.ruleId == 'new') {
        await api.createRule(payload);
      } else {
        payload['id'] = widget.ruleId!;
        await api.updateRule(widget.ruleId!, payload);
      }
      await ref.read(automationsProvider.notifier).reload();
      if (mounted) context.go('/automations');
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
    for (final c in _triggerCtrls.values) c.dispose();
    for (final c in _conditionCtrls) c.dispose();
    for (final c in _actionCtrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ruleId == null || widget.ruleId == 'new'
            ? 'New Automation'
            : 'Edit Automation'),
        actions: [
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)))
          else
            TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Basic info
            TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Required' : null),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextFormField(
                      controller: _priorityCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Priority'),
                      keyboardType: TextInputType.number)),
              const SizedBox(width: 16),
              const Text('Enabled'),
              Switch(
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v)),
            ]),
            const SizedBox(height: 16),

            // Trigger section
            const _SectionHeader(title: 'Trigger'),
            DropdownButtonFormField<String>(
              value: _triggerType,
              items: _triggerTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _triggerType = v!),
              decoration:
                  const InputDecoration(labelText: 'Trigger type'),
            ),
            ..._buildTriggerFields(),
            const SizedBox(height: 16),

            // Conditions section
            _SectionHeader(
              title: 'Conditions (AND)',
              action: IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => setState(() => _conditionCtrls.add(
                      TextEditingController(
                          text:
                              '{\n  "type": "device_state",\n  "device_id": "",\n  "attribute": "on",\n  "op": "eq",\n  "value": true\n}'),
                    )),
              ),
            ),
            ..._conditionCtrls.asMap().entries.map((e) => _JsonEditor(
                  ctrl: e.value,
                  onDelete: () =>
                      setState(() => _conditionCtrls.removeAt(e.key)),
                )),
            const SizedBox(height: 16),

            // Actions section
            _SectionHeader(
              title: 'Actions',
              action: IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => setState(() => _actionCtrls.add(
                      TextEditingController(
                          text:
                              '{\n  "type": "set_device_state",\n  "device_id": "",\n  "state": {"on": true}\n}'),
                    )),
              ),
            ),
            ..._actionCtrls.asMap().entries.map((e) => _JsonEditor(
                  ctrl: e.value,
                  onDelete: () =>
                      setState(() => _actionCtrls.removeAt(e.key)),
                )),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTriggerFields() {
    switch (_triggerType) {
      case 'device_state_changed':
        return [
          _TriggerField(
              ctrl: _triggerCtrls['device_id']!, label: 'Device ID'),
          _TriggerField(
              ctrl: _triggerCtrls['attribute']!,
              label: 'Attribute (optional)'),
          _TriggerField(
              ctrl: _triggerCtrls['to']!,
              label: 'To value (JSON, optional)'),
        ];
      case 'time_of_day':
        return [
          _TriggerField(
              ctrl: _triggerCtrls['time']!, label: 'Time (HH:MM:SS)'),
          _TriggerField(
              ctrl: _triggerCtrls['days']!,
              label: 'Days (comma-separated: Mon,Tue,...)'),
        ];
      case 'sun_event':
        return [
          StatefulBuilder(
            builder: (context, setState) => DropdownButtonFormField<String>(
              value: _triggerCtrls['event']!.text.isEmpty
                  ? 'sunset'
                  : _triggerCtrls['event']!.text,
              items: ['sunrise', 'sunset', 'solar_noon', 'civil_dawn', 'civil_dusk']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) {
                if (v != null) _triggerCtrls['event']!.text = v;
              },
              decoration:
                  const InputDecoration(labelText: 'Solar event'),
            ),
          ),
          _TriggerField(
              ctrl: _triggerCtrls['offset_minutes']!,
              label: 'Offset minutes',
              keyboardType: TextInputType.number),
        ];
      case 'webhook_received':
        return [
          _TriggerField(ctrl: _triggerCtrls['path']!, label: 'Path')
        ];
      case 'mqtt_message':
        return [
          _TriggerField(
              ctrl: _triggerCtrls['topic_pattern']!,
              label: 'Topic pattern')
        ];
      default:
        return [
          const Padding(
              padding: EdgeInsets.all(8),
              child: Text('No configuration needed.'))
        ];
    }
  }
}

class _TriggerField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final TextInputType keyboardType;
  const _TriggerField(
      {required this.ctrl,
      required this.label,
      this.keyboardType = TextInputType.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextFormField(
            controller: ctrl,
            decoration: InputDecoration(labelText: label),
            keyboardType: keyboardType),
      );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const _SectionHeader({required this.title, this.action});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (action != null) action!,
        ],
      );
}

class _JsonEditor extends StatelessWidget {
  final TextEditingController ctrl;
  final VoidCallback onDelete;
  const _JsonEditor({required this.ctrl, required this.onDelete});
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              TextFormField(
                controller: ctrl,
                maxLines: null,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(border: InputBorder.none),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Remove'),
                  onPressed: onDelete,
                ),
              ),
            ],
          ),
        ),
      );
}
