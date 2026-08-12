import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/schema/device_schema.dart';
import 'package:hc_web/features/devices/device_readings.dart';

/// What core now tells the UI about a device, and what the UI does with it.
///
/// Both fields are absent on almost every device today — a plugin has to have
/// been taught to send them — so "absent" is the case that must stay quiet.

DeviceState _device(Map<String, dynamic> json) => DeviceState.fromJson({
      'device_id': 'dev1',
      'plugin_id': 'plugin.x',
      'available': true,
      'attributes': <String, dynamic>{},
      ...json,
    });

void main() {
  group('hardware identity', () {
    test('is read from the wire when present', () {
      final d = _device({
        'manufacturer': 'Signify',
        'model': 'LCT015',
        'sw_version': '1.104.2',
        'parent_device_id': 'hue_bridge_1',
      });
      expect(d.manufacturer, 'Signify');
      expect(d.model, 'LCT015');
      expect(d.swVersion, '1.104.2');
      expect(d.parentDeviceId, 'hue_bridge_1');
    });

    /// The common case, and it must not become a row of "Unknown".
    test('is null when the plugin did not say', () {
      final d = _device({});
      expect(d.manufacturer, isNull);
      expect(d.model, isNull);
      expect(d.swVersion, isNull);
      expect(d.parentDeviceId, isNull);
    });

    /// copyWith is what the WS handler rebuilds a device through. Dropping a
    /// field here is how a device silently loses its schema on an availability
    /// event — the bug that comment in the model exists because of.
    test('survives copyWith', () {
      final d = _device({'manufacturer': 'Acme', 'sw_version': '2.0'});
      final after = d.copyWith(available: false);
      expect(after.manufacturer, 'Acme');
      expect(after.swVersion, '2.0');
    });
  });

  group('attribute category', () {
    test('a declared diagnostic is folded away', () {
      final s = AttributeSchema.fromJson({
        'kind': 'integer',
        'category': 'diagnostic',
      })!;
      expect(s.isDiagnostic, isTrue);
    });

    test('no category means primary', () {
      final s = AttributeSchema.fromJson({'kind': 'integer'})!;
      expect(s.category, isNull);
      expect(s.isDiagnostic, isFalse);
    });

    /// A category this build does not know is a newer core talking. Showing
    /// the attribute is the safe direction to be wrong in; swallowing it is
    /// not.
    test('an unknown category shows the attribute rather than hiding it', () {
      final s = AttributeSchema.fromJson({
        'kind': 'integer',
        'category': 'something_new',
      })!;
      expect(s.category, isNull);
      expect(s.isDiagnostic, isFalse);
    });
  });

  group('folding', () {
    /// The heuristic still carries every device with no schema, which is most
    /// of them.
    test('the name heuristic still applies', () {
      expect(isAdvancedReading('cc112_targetValue'), isTrue);
      expect(isAdvancedReading('temperature'), isFalse);
    });
  });
}
