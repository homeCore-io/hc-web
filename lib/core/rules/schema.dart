/// Rule vocabulary — the single source of truth for triggers, conditions and
/// actions, mirroring `core/crates/hc-types/src/rule.rs`.
///
/// Core derives serde's *default* representation on `Trigger`, `Condition`,
/// `Action`, `CompareOp` and `RunMode` (there is no `#[serde(tag = ...)]`), so
/// they are **externally tagged with PascalCase variant names**:
///
/// * struct variants → `{"DeviceStateChanged": {...}}`
/// * unit variants   → the bare string `"ManualTrigger"`
///
/// Beware: enums declared *elsewhere* keep their own casing. `DeviceChangeKind`
/// (device.rs) is `rename_all = "snake_case"`, so a `change_kind` field nested
/// inside a PascalCase trigger carries `"homecore"`, not `"Homecore"`.
///
/// These descriptors drive the wire codec *and* the rule editor's form
/// generation, so a new variant only has to be declared once, here.
library;

/// The value shape of a single field on a variant.
enum HcFieldKind {
  /// Free text.
  text,

  /// Rhai expression / script body.
  script,

  /// A device reference. Prefer `canonical_name` (e.g. `living_room.floor_lamp`)
  /// over a raw `device_id` — `rule_resolver.rs` accepts either, and the
  /// canonical name survives a device being replaced.
  deviceRef,
  deviceRefList,

  /// A device attribute name (e.g. `on`, `brightness`).
  attribute,

  /// Arbitrary JSON — a device state blob, an event payload, a compared value.
  json,

  integer,
  number,
  boolean,

  /// Wall-clock `HH:MM:SS`. The scheduler compares only hour and minute, so the
  /// editor must not offer a seconds field.
  time,

  /// Chrono `Weekday` list, serialized `["Mon", "Tue", ...]`.
  weekdays,

  modeRef,
  sceneRef,
  ruleRef,

  /// Recursive — a nested boolean condition tree.
  condition,
  conditionList,

  /// Recursive — a nested action list. Note these are bare `Action`s: the
  /// `enabled` wrapper exists only at the top level of a rule.
  actionList,

  /// `Vec<ConditionalBranch>` — the ELSE-IF chain.
  branchList,

  /// `Vec<ModeStateEntry>` / `ModeDelayEntry` / `ModeSceneEntry`.
  modeStateList,
  modeDelayList,
  modeSceneList,

  /// Closed enums, all PascalCase on the wire except `changeKind`.
  compareOp,
  sunEvent,
  buttonEvent,
  thresholdOp,
  periodicUnit,
  variableOp,
  modeCommand,
  logLevel,

  /// snake_case on the wire — see the library doc above.
  changeKind,
}

/// Wire values for the closed enums. PascalCase, matching the Rust variant
/// names, except [changeKindValues] which core renames to snake_case.
const compareOpValues = ['Eq', 'Ne', 'Gt', 'Gte', 'Lt', 'Lte'];
const sunEventValues = [
  'Sunrise',
  'Sunset',
  'SolarNoon',
  'CivilDawn',
  'CivilDusk',
];
const buttonEventValues = ['Pushed', 'Held', 'DoubleTapped', 'Released'];
const thresholdOpValues = ['Above', 'Below', 'CrossesAbove', 'CrossesBelow'];
const periodicUnitValues = ['Minutes', 'Hours', 'Days', 'Weeks'];
const variableOpValues = [
  'Set',
  'Add',
  'Subtract',
  'Multiply',
  'Divide',
  'Toggle',
];
const modeCommandValues = ['On', 'Off', 'Toggle'];
const logLevelValues = ['Trace', 'Debug', 'Info', 'Warn', 'Error'];
const changeKindValues = ['homecore', 'physical', 'external', 'unknown'];

/// Wire values for a [HcFieldKind] that maps to a closed enum, else `null`.
List<String>? enumValuesFor(HcFieldKind kind) => switch (kind) {
      HcFieldKind.compareOp => compareOpValues,
      HcFieldKind.sunEvent => sunEventValues,
      HcFieldKind.buttonEvent => buttonEventValues,
      HcFieldKind.thresholdOp => thresholdOpValues,
      HcFieldKind.periodicUnit => periodicUnitValues,
      HcFieldKind.variableOp => variableOpValues,
      HcFieldKind.modeCommand => modeCommandValues,
      HcFieldKind.logLevel => logLevelValues,
      HcFieldKind.changeKind => changeKindValues,
      _ => null,
    };

/// One field on a variant.
class HcField {
  const HcField(
    this.name,
    this.kind, {
    this.required = false,
    this.defaultValue,
    this.label,
    this.help,
  });

  /// Wire name, e.g. `device_id`.
  final String name;
  final HcFieldKind kind;

  /// Required fields are always emitted. Optional ones are omitted when null,
  /// matching core's `skip_serializing_if = "Option::is_none"`.
  final bool required;

  /// Seeded into a newly-created node so it is valid on first save.
  final Object? defaultValue;

  final String? label;
  final String? help;

  bool get isRecursive =>
      kind == HcFieldKind.condition ||
      kind == HcFieldKind.conditionList ||
      kind == HcFieldKind.actionList ||
      kind == HcFieldKind.branchList;
}

/// One variant of `Trigger`, `Condition` or `Action`.
class HcVariant {
  const HcVariant(
    this.tag, {
    required this.label,
    this.category = '',
    this.fields = const [],
    this.help,
  });

  /// PascalCase wire tag, e.g. `DeviceStateChanged`.
  final String tag;
  final String label;

  /// Groups the action palette — 34 actions is far too many for a flat list.
  final String category;
  final List<HcField> fields;
  final String? help;

  /// Unit variants serialize as a bare string rather than `{tag: {...}}`.
  /// A struct variant whose fields are all optional is still `{tag: {}}`.
  bool get isUnit => fields.isEmpty;
}

Map<String, HcVariant> _index(List<HcVariant> vs) => {
      for (final v in vs) v.tag: v,
    };

// ---------------------------------------------------------------------------
// Triggers (18)
// ---------------------------------------------------------------------------

final Map<String, HcVariant> kTriggers = _index([
  const HcVariant(
    'DeviceStateChanged',
    label: 'Device state changed',
    category: 'Device',
    fields: [
      HcField('device_id', HcFieldKind.deviceRef, required: true),
      HcField('device_ids', HcFieldKind.deviceRefList,
          label: 'Also fire for', help: 'Fires if any listed device changes.'),
      HcField('attribute', HcFieldKind.attribute,
          help: 'Leave empty to fire on any attribute.'),
      HcField('to', HcFieldKind.json, label: 'Changed to'),
      HcField('from', HcFieldKind.json, label: 'Changed from'),
      HcField('not_from', HcFieldKind.json, label: 'Not from'),
      HcField('not_to', HcFieldKind.json, label: 'Not to'),
      HcField('for_duration_secs', HcFieldKind.integer,
          label: 'And stays for (s)'),
      HcField('change_kind', HcFieldKind.changeKind, label: 'Change origin'),
      HcField('change_source', HcFieldKind.text, label: 'Change source'),
    ],
  ),
  const HcVariant(
    'DeviceAvailabilityChanged',
    label: 'Device came online / went offline',
    category: 'Device',
    fields: [
      HcField('device_id', HcFieldKind.deviceRef, required: true),
      HcField('to', HcFieldKind.boolean, label: 'Online'),
      HcField('for_duration_secs', HcFieldKind.integer,
          label: 'And stays for (s)'),
    ],
  ),
  const HcVariant(
    'ButtonEvent',
    label: 'Button pushed / held',
    category: 'Device',
    fields: [
      HcField('device_id', HcFieldKind.deviceRef, required: true),
      HcField('button_number', HcFieldKind.integer,
          help: 'Leave empty for any button.'),
      HcField('event', HcFieldKind.buttonEvent,
          required: true, defaultValue: 'Pushed'),
    ],
  ),
  const HcVariant(
    'NumericThreshold',
    label: 'Numeric threshold crossed',
    category: 'Device',
    help: 'Unlike a state change, this fires only on the crossing edge.',
    fields: [
      HcField('device_id', HcFieldKind.deviceRef, required: true),
      HcField('attribute', HcFieldKind.attribute, required: true),
      HcField('op', HcFieldKind.thresholdOp,
          required: true, defaultValue: 'CrossesAbove'),
      HcField('value', HcFieldKind.number, required: true, defaultValue: 0),
      HcField('for_duration_secs', HcFieldKind.integer, label: 'Debounce (s)'),
    ],
  ),
  const HcVariant(
    'DeviceBatteryLow',
    label: 'Battery low',
    category: 'Device',
    fields: [
      HcField('device_id', HcFieldKind.deviceRef,
          help: 'Leave empty for any battery device.'),
    ],
  ),
  const HcVariant(
    'DeviceBatteryRecovered',
    label: 'Battery recovered',
    category: 'Device',
    fields: [
      HcField('device_id', HcFieldKind.deviceRef,
          help: 'Leave empty for any battery device.'),
    ],
  ),
  const HcVariant(
    'TimeOfDay',
    label: 'At a time of day',
    category: 'Time',
    help: 'The scheduler ticks once a minute — seconds are ignored.',
    fields: [
      HcField('time', HcFieldKind.time,
          required: true, defaultValue: '00:00:00'),
      HcField('days', HcFieldKind.weekdays,
          required: true,
          defaultValue: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']),
    ],
  ),
  const HcVariant(
    'SunEvent',
    label: 'At a solar event',
    category: 'Time',
    fields: [
      HcField('event', HcFieldKind.sunEvent,
          required: true, defaultValue: 'Sunset'),
      HcField('offset_minutes', HcFieldKind.integer,
          required: true, defaultValue: 0, label: 'Offset (min)'),
    ],
  ),
  const HcVariant(
    'Cron',
    label: 'On a cron schedule',
    category: 'Time',
    fields: [
      HcField('expression', HcFieldKind.text,
          required: true,
          defaultValue: '0 0 * * * *',
          help: 'Six fields: sec min hour day-of-month month day-of-week.'),
    ],
  ),
  const HcVariant(
    'Periodic',
    label: 'Every N minutes / hours',
    category: 'Time',
    fields: [
      HcField('every_n', HcFieldKind.integer, required: true, defaultValue: 15),
      HcField('unit', HcFieldKind.periodicUnit,
          required: true, defaultValue: 'Minutes'),
    ],
  ),
  const HcVariant(
    'CalendarEvent',
    label: 'On a calendar event',
    category: 'Time',
    fields: [
      HcField('calendar_id', HcFieldKind.text,
          help: 'Stem of the .ics filename. Empty matches any calendar.'),
      HcField('title_contains', HcFieldKind.text),
      // NOT required: core defaults it. Demanding it here forced the user to
      // fill in a field that has a perfectly good default.
      HcField('offset_minutes', HcFieldKind.integer,
          defaultValue: 0, help: 'Negative fires before start.'),
    ],
  ),
  const HcVariant(
    'ModeChanged',
    label: 'Mode turned on / off',
    category: 'Hub',
    fields: [
      HcField('mode_id', HcFieldKind.modeRef,
          label: 'Mode', help: 'Empty matches any mode.'),
      HcField('to', HcFieldKind.boolean, label: 'Turned on'),
    ],
  ),
  const HcVariant(
    'HubVariableChanged',
    label: 'Hub variable changed',
    category: 'Hub',
    fields: [
      HcField('name', HcFieldKind.text, help: 'Empty watches every hub var.'),
    ],
  ),
  const HcVariant(
    'SystemStarted',
    label: 'On system start',
    category: 'Hub',
  ),
  const HcVariant(
    'ManualTrigger',
    label: 'Manual only',
    category: 'Hub',
    help: 'Never fires on its own — run it by hand or from another rule.',
  ),
  const HcVariant(
    'CustomEvent',
    label: 'On a custom event',
    category: 'Integration',
    fields: [
      HcField('event_type', HcFieldKind.text, required: true),
    ],
  ),
  const HcVariant(
    'MqttMessage',
    label: 'On an MQTT message',
    category: 'Integration',
    fields: [
      HcField('topic_pattern', HcFieldKind.text, required: true),
      HcField('payload', HcFieldKind.text, help: 'Exact raw payload match.'),
      HcField('value_path', HcFieldKind.text,
          help: 'JSON pointer, e.g. /temperature'),
      HcField('value_op', HcFieldKind.compareOp),
      HcField('value_cmp', HcFieldKind.json),
    ],
  ),
  const HcVariant(
    'WebhookReceived',
    label: 'On a webhook call',
    category: 'Integration',
    fields: [
      HcField('path', HcFieldKind.text,
          required: true,
          help: 'The path segment doubles as the shared secret.'),
    ],
  ),
]);

// ---------------------------------------------------------------------------
// Conditions (13)
// ---------------------------------------------------------------------------

final Map<String, HcVariant> kConditions = _index([
  const HcVariant(
    'DeviceState',
    label: 'Device state is',
    category: 'Device',
    fields: [
      HcField('device_id', HcFieldKind.deviceRef, required: true),
      HcField('attribute', HcFieldKind.attribute, required: true),
      HcField('op', HcFieldKind.compareOp, required: true, defaultValue: 'Eq'),
      HcField('value', HcFieldKind.json, required: true, defaultValue: true),
    ],
  ),
  const HcVariant(
    'TimeElapsed',
    label: 'Attribute unchanged for',
    category: 'Device',
    fields: [
      HcField('device_id', HcFieldKind.deviceRef, required: true),
      HcField('attribute', HcFieldKind.attribute, required: true),
      HcField('duration_secs', HcFieldKind.integer,
          required: true, defaultValue: 300),
    ],
  ),
  const HcVariant(
    'DeviceLastChange',
    label: 'Last change came from',
    category: 'Device',
    help: 'Filter on the provenance of the most recent change.',
    fields: [
      HcField('device_id', HcFieldKind.deviceRef, required: true),
      HcField('kind', HcFieldKind.changeKind),
      HcField('source', HcFieldKind.text),
      HcField('actor_id', HcFieldKind.text),
      HcField('actor_name', HcFieldKind.text),
    ],
  ),
  const HcVariant(
    'TimeWindow',
    label: 'Within a time window',
    category: 'Time',
    fields: [
      HcField('start', HcFieldKind.time,
          required: true, defaultValue: '00:00:00'),
      HcField('end', HcFieldKind.time,
          required: true, defaultValue: '23:59:00'),
    ],
  ),
  const HcVariant(
    'CalendarActive',
    label: 'Calendar event active',
    category: 'Time',
    fields: [
      HcField('calendar_id', HcFieldKind.text),
      HcField('title_contains', HcFieldKind.text),
    ],
  ),
  const HcVariant(
    'ModeIs',
    label: 'Mode is',
    category: 'Hub',
    fields: [
      HcField('mode_id', HcFieldKind.modeRef, label: 'Mode', required: true),
      HcField('on', HcFieldKind.boolean, required: true, defaultValue: true),
    ],
  ),
  const HcVariant(
    'HubVariable',
    label: 'Hub variable is',
    category: 'Hub',
    fields: [
      HcField('name', HcFieldKind.text, required: true),
      HcField('op', HcFieldKind.compareOp, required: true, defaultValue: 'Eq'),
      HcField('value', HcFieldKind.json, required: true),
    ],
  ),
  const HcVariant(
    'PrivateBooleanIs',
    label: 'Private boolean is',
    category: 'Hub',
    fields: [
      HcField('name', HcFieldKind.text, required: true),
      HcField('value', HcFieldKind.boolean, required: true, defaultValue: true),
    ],
  ),
  const HcVariant(
    'Not',
    label: 'NOT',
    category: 'Logic',
    fields: [
      HcField('condition', HcFieldKind.condition, required: true),
    ],
  ),
  const HcVariant(
    'And',
    label: 'ALL of',
    category: 'Logic',
    fields: [
      HcField('conditions', HcFieldKind.conditionList, required: true),
    ],
  ),
  const HcVariant(
    'Or',
    label: 'ANY of',
    category: 'Logic',
    fields: [
      HcField('conditions', HcFieldKind.conditionList, required: true),
    ],
  ),
  const HcVariant(
    'Xor',
    label: 'EXACTLY ONE of',
    category: 'Logic',
    fields: [
      HcField('conditions', HcFieldKind.conditionList, required: true),
    ],
  ),
  const HcVariant(
    'ScriptExpression',
    label: 'Script expression',
    category: 'Script',
    fields: [
      HcField('script', HcFieldKind.script, required: true),
    ],
  ),
]);

// ---------------------------------------------------------------------------
// Actions (34)
// ---------------------------------------------------------------------------

final Map<String, HcVariant> kActions = _index([
  // -- Device --------------------------------------------------------------
  const HcVariant(
    'SetDeviceState',
    label: 'Set device state',
    category: 'Device',
    fields: [
      HcField('device_id', HcFieldKind.deviceRef, required: true),
      HcField('state', HcFieldKind.json,
          required: true, defaultValue: {'on': true}),
      // NOT required: core defaults it. Marking it required is what put it in
      // every node the editor created, which is what made "Refine · 1 set" fire
      // on every action of every rule.
      HcField('track_event_value', HcFieldKind.boolean,
          defaultValue: false,
          label: 'Mirror the trigger value',
          help:
              'Use the triggering event\'s value instead of the state above.'),
    ],
  ),
  const HcVariant(
    'SetDeviceStatePerMode',
    label: 'Set device state per mode',
    category: 'Device',
    fields: [
      HcField('device_id', HcFieldKind.deviceRef, required: true),
      HcField('modes', HcFieldKind.modeStateList, required: true),
      HcField('default_state', HcFieldKind.json),
    ],
  ),
  const HcVariant(
    'FadeDevice',
    label: 'Fade device',
    category: 'Device',
    fields: [
      HcField('device_id', HcFieldKind.deviceRef, required: true),
      HcField('target', HcFieldKind.json, required: true),
      HcField('duration_secs', HcFieldKind.integer,
          required: true, defaultValue: 30),
      HcField('steps', HcFieldKind.integer, help: 'Clamped to 2–100.'),
    ],
  ),
  const HcVariant(
    'CaptureDeviceState',
    label: 'Capture device state',
    category: 'Device',
    fields: [
      HcField('key', HcFieldKind.text, required: true),
      HcField('device_ids', HcFieldKind.deviceRefList, required: true),
    ],
  ),
  const HcVariant(
    'RestoreDeviceState',
    label: 'Restore device state',
    category: 'Device',
    fields: [
      HcField('key', HcFieldKind.text, required: true),
    ],
  ),

  // -- Flow ----------------------------------------------------------------
  const HcVariant(
    'Conditional',
    label: 'IF / ELSE',
    category: 'Flow',
    fields: [
      HcField('condition', HcFieldKind.script, required: true),
      HcField('then_actions', HcFieldKind.actionList, required: true),
      HcField('else_if', HcFieldKind.branchList),
      HcField('else_actions', HcFieldKind.actionList),
    ],
  ),
  const HcVariant(
    'Parallel',
    label: 'Run in parallel',
    category: 'Flow',
    fields: [
      HcField('actions', HcFieldKind.actionList, required: true),
    ],
  ),
  const HcVariant(
    'RepeatUntil',
    label: 'Repeat until',
    category: 'Flow',
    help: 'Checked after each pass — the body always runs at least once.',
    fields: [
      HcField('condition', HcFieldKind.script, required: true),
      HcField('actions', HcFieldKind.actionList, required: true),
      HcField('max_iterations', HcFieldKind.integer),
      HcField('interval_ms', HcFieldKind.integer),
    ],
  ),
  const HcVariant(
    'RepeatWhile',
    label: 'Repeat while',
    category: 'Flow',
    help: 'Checked before each pass — the body may never run.',
    fields: [
      HcField('condition', HcFieldKind.script, required: true),
      HcField('actions', HcFieldKind.actionList, required: true),
      HcField('max_iterations', HcFieldKind.integer),
      HcField('interval_ms', HcFieldKind.integer),
    ],
  ),
  const HcVariant(
    'RepeatCount',
    label: 'Repeat N times',
    category: 'Flow',
    fields: [
      HcField('count', HcFieldKind.integer, required: true, defaultValue: 2),
      HcField('actions', HcFieldKind.actionList, required: true),
      HcField('interval_ms', HcFieldKind.integer),
    ],
  ),
  const HcVariant(
    'StopRuleChain',
    label: 'Stop the rule chain',
    category: 'Flow',
  ),
  const HcVariant(
    'ExitRule',
    label: 'Exit this rule',
    category: 'Flow',
  ),

  // -- Delay / wait --------------------------------------------------------
  const HcVariant(
    'Delay',
    label: 'Wait',
    category: 'Delay',
    fields: [
      HcField('duration_secs', HcFieldKind.integer,
          required: true, defaultValue: 60),
      // NOT required: core defaults it.
      HcField('cancelable', HcFieldKind.boolean, defaultValue: false),
      HcField('cancel_key', HcFieldKind.text),
    ],
  ),
  const HcVariant(
    'DelayPerMode',
    label: 'Wait, per mode',
    category: 'Delay',
    fields: [
      HcField('modes', HcFieldKind.modeDelayList, required: true),
      HcField('default_secs', HcFieldKind.integer),
    ],
  ),
  const HcVariant(
    'WaitForEvent',
    label: 'Wait for an event',
    category: 'Delay',
    fields: [
      HcField('event_type', HcFieldKind.text),
      HcField('device_id', HcFieldKind.deviceRef),
      HcField('attribute', HcFieldKind.attribute),
      HcField('timeout_ms', HcFieldKind.integer),
    ],
  ),
  const HcVariant(
    'WaitForExpression',
    label: 'Wait for an expression',
    category: 'Delay',
    fields: [
      HcField('expression', HcFieldKind.script, required: true),
      HcField('poll_interval_ms', HcFieldKind.integer),
      HcField('timeout_ms', HcFieldKind.integer),
      HcField('hold_duration_ms', HcFieldKind.integer),
    ],
  ),
  const HcVariant(
    'CancelDelays',
    label: 'Cancel pending delays',
    category: 'Delay',
    fields: [
      HcField('key', HcFieldKind.text, help: 'Empty cancels all in this rule.'),
    ],
  ),
  const HcVariant(
    'CancelRuleTimers',
    label: 'Cancel a rule\'s timers',
    category: 'Delay',
    fields: [
      HcField('rule_id', HcFieldKind.ruleRef, help: 'Empty means this rule.'),
    ],
  ),

  // -- Mode / scene --------------------------------------------------------
  const HcVariant(
    'SetMode',
    label: 'Set mode',
    category: 'Mode',
    fields: [
      HcField('mode_id', HcFieldKind.modeRef, label: 'Mode', required: true),
      HcField('command', HcFieldKind.modeCommand,
          required: true, defaultValue: 'On'),
    ],
  ),
  const HcVariant(
    'ActivateScenePerMode',
    label: 'Activate scene per mode',
    category: 'Mode',
    help: 'Native scenes only. Plugin scene-devices are fired via '
        'Set device state.',
    fields: [
      HcField('modes', HcFieldKind.modeSceneList, required: true),
      HcField('default_scene_id', HcFieldKind.sceneRef),
    ],
  ),

  // -- Notify --------------------------------------------------------------
  const HcVariant(
    'Notify',
    label: 'Send a notification',
    category: 'Notify',
    fields: [
      HcField('channel', HcFieldKind.text,
          required: true,
          defaultValue: 'all',
          help: '"all" fans out to every registered channel.'),
      HcField('message', HcFieldKind.text, required: true),
      HcField('title', HcFieldKind.text),
    ],
  ),
  const HcVariant(
    'LogMessage',
    label: 'Write to the log',
    category: 'Notify',
    fields: [
      HcField('message', HcFieldKind.text, required: true),
      HcField('level', HcFieldKind.logLevel),
    ],
  ),
  const HcVariant(
    'Comment',
    label: 'Comment',
    category: 'Notify',
    fields: [
      HcField('text', HcFieldKind.text, required: true),
    ],
  ),

  // -- Variables / script --------------------------------------------------
  const HcVariant(
    'RunScript',
    label: 'Run a script',
    category: 'Script',
    fields: [
      HcField('script', HcFieldKind.script, required: true),
    ],
  ),
  const HcVariant(
    'SetVariable',
    label: 'Set a rule variable',
    category: 'Script',
    fields: [
      HcField('name', HcFieldKind.text, required: true),
      HcField('value', HcFieldKind.json, required: true),
      HcField('op', HcFieldKind.variableOp),
    ],
  ),
  const HcVariant(
    'SetHubVariable',
    label: 'Set a hub variable',
    category: 'Script',
    fields: [
      HcField('name', HcFieldKind.text, required: true),
      HcField('value', HcFieldKind.json, required: true),
      HcField('op', HcFieldKind.variableOp),
    ],
  ),
  const HcVariant(
    'SetPrivateBoolean',
    label: 'Set a private boolean',
    category: 'Script',
    fields: [
      HcField('name', HcFieldKind.text, required: true),
      HcField('value', HcFieldKind.boolean, required: true, defaultValue: true),
    ],
  ),

  // -- Rule control --------------------------------------------------------
  const HcVariant(
    'RunRuleActions',
    label: 'Run another rule\'s actions',
    category: 'Rule control',
    fields: [
      HcField('rule_id', HcFieldKind.ruleRef, required: true),
    ],
  ),
  const HcVariant(
    'PauseRule',
    label: 'Pause a rule',
    category: 'Rule control',
    fields: [
      HcField('rule_id', HcFieldKind.ruleRef, required: true),
    ],
  ),
  const HcVariant(
    'ResumeRule',
    label: 'Resume a rule',
    category: 'Rule control',
    fields: [
      HcField('rule_id', HcFieldKind.ruleRef, required: true),
    ],
  ),

  // -- Integration ---------------------------------------------------------
  const HcVariant(
    'PublishMqtt',
    label: 'Publish MQTT',
    category: 'Integration',
    fields: [
      HcField('topic', HcFieldKind.text, required: true),
      HcField('payload', HcFieldKind.text, required: true),
      HcField('retain', HcFieldKind.boolean,
          required: true, defaultValue: false),
    ],
  ),
  const HcVariant(
    'CallService',
    label: 'Call an HTTP service',
    category: 'Integration',
    fields: [
      HcField('url', HcFieldKind.text, required: true),
      HcField('method', HcFieldKind.text, required: true, defaultValue: 'POST'),
      HcField('body', HcFieldKind.json),
      HcField('timeout_ms', HcFieldKind.integer),
      HcField('retries', HcFieldKind.integer),
      HcField('response_event', HcFieldKind.text),
    ],
  ),
  const HcVariant(
    'FireEvent',
    label: 'Fire a custom event',
    category: 'Integration',
    fields: [
      HcField('event_type', HcFieldKind.text, required: true),
      HcField('payload', HcFieldKind.json, required: true),
    ],
  ),
  const HcVariant(
    'PingHost',
    label: 'Ping a host',
    category: 'Integration',
    fields: [
      HcField('host', HcFieldKind.text, required: true),
      HcField('count', HcFieldKind.integer),
      HcField('timeout_ms', HcFieldKind.integer),
      HcField('then_actions', HcFieldKind.actionList, label: 'If reachable'),
      HcField('else_actions', HcFieldKind.actionList, label: 'If unreachable'),
      HcField('response_event', HcFieldKind.text),
    ],
  ),
]);

/// Palette categories, in the order the editor should present them.
const kActionCategories = [
  'Device',
  'Flow',
  'Delay',
  'Mode',
  'Notify',
  'Script',
  'Rule control',
  'Integration',
];

/// Trigger categories, used by the palette and by the list page's filter chips.
const kTriggerCategories = ['Device', 'Time', 'Hub', 'Integration'];

/// Condition categories.
const kConditionCategories = ['Device', 'Time', 'Hub', 'Logic', 'Script'];
