import '../../core/api/glue_api.dart';

/// The `config` map sent with a new helper.
///
/// Pure, and separate from the dialog, because the interesting part is not the
/// widgets: it is that a blank or unparseable field must fall back to the same
/// default the hub would have applied, rather than sending null and creating a
/// number whose range is missing.
Map<String, Object?> glueConfigFor(
  GlueConfig kind, {
  String min = '',
  String max = '',
  String step = '',
  String unit = '',
  List<String> options = const [],
  List<String> members = const [],
  String attribute = 'on',
  String mode = 'any',
  bool expect = true,
  int durationSecs = 0,
  bool repeat = false,
  String maxLength = '',
  bool hasDate = true,
  bool hasTime = true,
  String sourceDeviceId = '',
  String sourceAttribute = 'value',
  String threshold = '',
  String hysteresis = '',
}) {
  switch (kind) {
    case GlueConfig.timer:
      return {
        // A timer created without one counts down from zero, which is a timer
        // that finishes the instant it starts.
        'duration_secs': durationSecs,
        'repeat': repeat,
      };

    case GlueConfig.counter:
      // The hub defaults step to 1 and leaves min/max unset, which means
      // unbounded — so a blank field must send nothing rather than a zero that
      // would silently floor the counter.
      return {
        'step': num.tryParse(step.trim()) ?? 1,
        if (num.tryParse(min.trim()) case final v?) 'min': v,
        if (num.tryParse(max.trim()) case final v?) 'max': v,
      };

    case GlueConfig.text:
      // Absent means unlimited; zero would mean a text helper that can hold
      // nothing at all.
      return {
        if (int.tryParse(maxLength.trim()) case final v? when v > 0)
          'max_length': v,
      };

    case GlueConfig.datetime:
      return {'has_date': hasDate, 'has_time': hasTime};

    case GlueConfig.threshold:
      return {
        'source_device_id': sourceDeviceId,
        'source_attribute':
            sourceAttribute.trim().isEmpty ? 'value' : sourceAttribute.trim(),
        'threshold': num.tryParse(threshold.trim()) ?? 0,
        // The flap guard. Zero is a legitimate value — it means "switch
        // exactly on the line" — so a blank field sends it rather than
        // omitting the key and leaving whatever was there before.
        'hysteresis': num.tryParse(hysteresis.trim()) ?? 0,
      };

    case GlueConfig.number:
      return {
        // Defaults mirror hc-api's create_glue, so leaving a field alone
        // produces exactly what the hub would have produced anyway.
        'min': num.tryParse(min.trim()) ?? 0,
        'max': num.tryParse(max.trim()) ?? 100,
        'step': num.tryParse(step.trim()) ?? 1,
        if (unit.trim().isNotEmpty) 'unit': unit.trim(),
      };

    case GlueConfig.select:
      return {'options': [...options]};

    case GlueConfig.group:
      return {
        'members': [...members],
        // The hub defaults these too; sending them explicitly keeps the
        // created device matching what the dialog showed.
        'attribute': attribute.trim().isEmpty ? 'on' : attribute.trim(),
        'mode': mode,
        // Which of the attribute's two states counts. Without it a group can
        // only ask "are any of these ON", so "all deck doors closed" is
        // unexpressible.
        'expect': expect,
      };

    case GlueConfig.none:
      return const {};
  }
}
