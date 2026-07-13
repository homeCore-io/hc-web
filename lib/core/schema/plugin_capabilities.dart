/// Plugin capability manifests — `GET /api/v1/plugins/{id}/capabilities`.
///
/// Mirrors `core/crates/hc-types/src/plugin_capabilities.rs`, whose own doc
/// comment states the point plainly: the UI reads this "to render/expose
/// plugin-specific actions **without plugin-specific code**".
///
/// On a real install this is 25 actions across 7 plugins — Z-Wave inclusion,
/// Hue/Sonos discovery, Ecowitt gateway configuration — none of which the UI
/// exposed before. Every one of them arrives here with a label, a parameter
/// schema and a required role, which is everything a form needs.
library;

/// Who may invoke an action. Core enforces this too (403), but a button the
/// user cannot press should be disabled rather than merely rejected.
enum RequiresRole {
  admin,
  user,
  readOnly;

  static RequiresRole fromWire(String? v) => switch (v) {
        'admin' => RequiresRole.admin,
        'read_only' => RequiresRole.readOnly,
        _ => RequiresRole.user,
      };

  /// Roles are ordered: an admin satisfies everything.
  bool satisfiedBy(String? role) => switch (this) {
        RequiresRole.admin => role == 'admin',
        RequiresRole.user => role == 'admin' || role == 'user',
        RequiresRole.readOnly => role != null,
      };
}

/// One parameter of an action.
///
/// Core freezes the accepted JSON-Schema keywords to a subset:
/// `type, default, enum, required, minimum, maximum` (plus `description`, which
/// every plugin in the wild actually uses).
class ParamSpec {
  const ParamSpec({
    required this.name,
    required this.type,
    this.description,
    this.defaultValue,
    this.options,
    this.minimum,
    this.maximum,
    this.required = false,
  });

  final String name;

  /// `string` | `integer` | `number` | `boolean`, per the frozen subset.
  final String type;

  final String? description;
  final Object? defaultValue;

  /// The `enum` keyword — a fixed value set.
  final List<String>? options;

  final num? minimum;
  final num? maximum;
  final bool required;

  bool get hasRange => minimum != null && maximum != null;

  factory ParamSpec.fromJson(String name, Map json) => ParamSpec(
        name: name,
        type: json['type'] as String? ?? 'string',
        description: json['description'] as String?,
        defaultValue: json['default'],
        options: (json['enum'] as List?)?.map((e) => '$e').toList(),
        minimum: json['minimum'] as num?,
        maximum: json['maximum'] as num?,
        required: json['required'] as bool? ?? false,
      );
}

class PluginAction {
  const PluginAction({
    required this.id,
    required this.label,
    this.description,
    this.params = const [],
    this.stream = false,
    this.cancelable = false,
    this.concurrency = 'multi',
    this.requiresRole = RequiresRole.user,
    this.timeoutMs,
    this.itemKey,
    this.itemOperations,
  });

  final String id;
  final String label;
  final String? description;
  final List<ParamSpec> params;

  /// Streaming actions reply over SSE at
  /// `/plugins/{id}/command/{request_id}/stream` instead of returning a value.
  final bool stream;

  final bool cancelable;

  /// `single` means a second invocation is rejected with 409 + the active
  /// request id, so the UI should offer to attach to that run rather than
  /// starting another.
  final String concurrency;

  final RequiresRole requiresRole;
  final int? timeoutMs;

  /// Names the field inside an `item` event's `data` that identifies it, so a
  /// later `update` revises the row it already produced instead of appending a
  /// near-duplicate. Core requires it whenever `item_operations` is set.
  final String? itemKey;

  /// Which of `add` / `update` / `remove` this action's `item` events use.
  final List<String>? itemOperations;

  bool get isSingleton => concurrency == 'single';

  factory PluginAction.fromJson(Map json) {
    final rawParams = json['params'];
    return PluginAction(
      id: json['id'] as String,
      label: json['label'] as String? ?? json['id'] as String,
      description: json['description'] as String?,
      params: rawParams is Map
          ? [
              for (final e in rawParams.entries)
                ParamSpec.fromJson(e.key as String, e.value as Map),
            ]
          : const [],
      stream: json['stream'] as bool? ?? false,
      cancelable: json['cancelable'] as bool? ?? false,
      concurrency: json['concurrency'] as String? ?? 'multi',
      requiresRole: RequiresRole.fromWire(json['requires_role'] as String?),
      timeoutMs: json['timeout_ms'] as int?,
      itemKey: json['item_key'] as String?,
      itemOperations:
          (json['item_operations'] as List?)?.map((e) => '$e').toList(),
    );
  }

  /// The body for `POST /plugins/{id}/command`: the action id plus the params,
  /// flattened alongside it — core does not nest them.
  Map<String, Object?> commandBody(Map<String, Object?> values) => {
        'action': id,
        ...values,
      };
}

class PluginCapabilities {
  const PluginCapabilities({
    required this.pluginId,
    this.spec = '1',
    this.actions = const [],
  });

  final String pluginId;
  final String spec;
  final List<PluginAction> actions;

  factory PluginCapabilities.fromJson(Map json) => PluginCapabilities(
        pluginId: json['plugin_id'] as String? ?? '',
        spec: json['spec'] as String? ?? '1',
        actions: [
          for (final a in (json['actions'] as List? ?? const []))
            PluginAction.fromJson(a as Map),
        ],
      );
}

/// The stages a streaming action emits. Core freezes this envelope, and
/// `error` is always terminal.
enum ActionStage {
  progress,
  item,
  awaitingUser,
  warning,
  complete,
  error,
  canceled,
  timeout;

  static ActionStage? fromWire(String? v) => switch (v) {
        'progress' => ActionStage.progress,
        'item' => ActionStage.item,
        'awaiting_user' => ActionStage.awaitingUser,
        'warning' => ActionStage.warning,
        'complete' => ActionStage.complete,
        'error' => ActionStage.error,
        // Synthesised by core when a run times out or the plugin drops.
        'canceled' => ActionStage.canceled,
        'timeout' => ActionStage.timeout,
        _ => null,
      };

  /// Terminal stages close the SSE stream. The UI must stop waiting on all of
  /// them, not just `complete`, or a failed Z-Wave inclusion spins forever.
  bool get isTerminal =>
      this == complete || this == error || this == canceled || this == timeout;

  bool get isFailure => this == error || this == timeout;
}

/// One event off the SSE stream.
class ActionEvent {
  const ActionEvent({
    required this.stage,
    this.message,
    this.percent,
    this.label,
    this.op,
    this.data,
  });

  final ActionStage stage;
  final String? message;
  final num? percent;
  final String? label;

  /// For `item` events: `add` | `update` | `remove`.
  final String? op;

  final Object? data;

  factory ActionEvent.fromJson(Map json) => ActionEvent(
        stage: ActionStage.fromWire(json['stage'] as String?) ??
            ActionStage.progress,
        message: json['message'] as String?,
        percent: json['percent'] as num?,
        label: json['label'] as String?,
        op: json['op'] as String?,
        data: json['data'],
      );
}
