import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/features/plugins/config_descriptor/descriptor.dart';
import 'package:hc_web/features/plugins/config_descriptor/descriptor_validation.dart';

/// The Caséta devices table, as the plugin actually publishes it.
CfgField devicesTable() => CfgField.fromJson({
      'key': 'devices',
      'kind': 'table',
      'label': 'Devices',
      'render': 'list',
      'group_by': 'area',
      'key_by': 'integration_id',
      'item': [
        {'key': 'integration_id', 'kind': 'int', 'label': 'Integration ID'},
        {'key': 'name', 'kind': 'text', 'label': 'Name'},
        {
          'key': 'kind',
          'kind': 'select',
          'label': 'Kind',
          'prompt_when_empty': true,
          'options': [
            {'value': 'switch', 'label': 'Switch'},
            {'value': 'pico', 'label': 'Pico remote'},
          ],
        },
        {'key': 'area', 'kind': 'select', 'label': 'Room'},
      ],
    });

void main() {
  _sourceBoundListColumnTests();
  group('descriptor parsing', () {
    test('a list table carries its render, grouping and identity', () {
      final f = devicesTable();
      expect(f.render, 'list');
      expect(f.groupBy, 'area');
      expect(f.keyBy, 'integration_id');
    });

    test('prompt_when_empty is per column and defaults off', () {
      final cols = devicesTable().itemFields!;
      final kind = cols.firstWhere((c) => c.key == 'kind');
      final name = cols.firstWhere((c) => c.key == 'name');
      expect(kind.promptWhenEmpty, isTrue);
      expect(name.promptWhenEmpty, isFalse);
    });

    test('wanting a value is not requiring one', () {
      // The distinction the whole feature turns on: an imported row has no
      // kind and must still save, because the plugin skips such a device and
      // logs it rather than failing.
      final kind =
          devicesTable().itemFields!.firstWhere((c) => c.key == 'kind');
      expect(kind.required, isFalse);
      expect(valueProblem(kind, null), isNull);
    });
  });

  group('adding a row', () {
    test('an empty table still yields a list you can add to', () {
      // The whole "add your first thermostat/device" flow: with no stored
      // value, this returned `const []` and the add button threw
      // `Unsupported operation: add`, so the first row could never be created.
      final rows = indexedRowsOf(null);
      expect(rows, isEmpty);
      expect(() => rows.add((index: 0, row: <String, dynamic>{})),
          returnsNormally);
    });

    test('existing rows are copies, addressed by their stored index', () {
      final stored = [
        {'integration_id': 2, 'kind': 'switch'},
        {'integration_id': 5, 'kind': 'pico'},
      ];
      final rows = indexedRowsOf(stored);
      expect(rows.map((e) => e.index), [0, 1]);
      rows[0].row['kind'] = 'edited';
      expect(stored[0]['kind'], 'switch', reason: 'must not mutate the source');
    });

    test('a new row starts at the defaults the descriptor declares', () {
      // A column that publishes a default is answering "what if you do not
      // choose" — a blank there misrepresents what the plugin will do.
      final cols = CfgField.fromJson({
        'key': 'thermostats',
        'kind': 'table',
        'item': [
          {'key': 'id', 'kind': 'text', 'prompt_when_empty': true},
          {'key': 'aggregation', 'kind': 'select', 'default': 'average'},
          {'key': 'setpoint', 'kind': 'float', 'default': 20.5},
        ],
      }).itemFields!;
      expect(newRowFor(cols),
          {'id': '', 'aggregation': 'average', 'setpoint': 20.5});
    });
  });

  group('attention', () {
    // Mirrors _rowNeedsAttention: any prompt_when_empty column with no value.
    bool needsAttention(CfgField table, Map<String, dynamic> row) {
      for (final c in table.itemFields ?? const <CfgField>[]) {
        if (!c.promptWhenEmpty || c.key == null) continue;
        final v = row[c.key];
        if (v == null || (v is String && v.isEmpty)) return true;
      }
      return false;
    }

    test('a row missing the prompted column wants attention', () {
      final t = devicesTable();
      expect(needsAttention(t, {'integration_id': 2, 'name': 'Zone'}), isTrue);
      expect(needsAttention(t, {'integration_id': 2, 'kind': ''}), isTrue);
      expect(
          needsAttention(t, {'integration_id': 2, 'kind': 'switch'}), isFalse);
    });

    test('a missing column that is not prompted is ignored', () {
      // No room is a normal state — it must not read as unfinished.
      expect(needsAttention(devicesTable(), {'kind': 'pico'}), isFalse);
    });
  });

  group('grouping', () {
    // Mirrors the renderer: group by a column's displayed value, empty last.
    List<String> groupOrder(CfgField table, List<Map<String, dynamic>> rows) {
      final key = table.groupBy!;
      final seen = <String>{};
      for (final r in rows) {
        seen.add('${r[key] ?? ''}');
      }
      final ordered = seen.toList()
        ..sort((a, b) => a.isEmpty
            ? 1
            : b.isEmpty
                ? -1
                : a.compareTo(b));
      return ordered;
    }

    test('groups sort alphabetically with unassigned last', () {
      final rows = <Map<String, dynamic>>[
        {'area': 'Outdoor'},
        {'area': ''},
        {'area': 'Family Room'},
        {'area': 'Living Room'},
      ];
      expect(groupOrder(devicesTable(), rows),
          ['Family Room', 'Living Room', 'Outdoor', '']);
    });

    test('rows with no room collect into one bucket, not several', () {
      final rows = <Map<String, dynamic>>[
        {'name': 'a'},
        {'area': '', 'name': 'b'},
        {'area': null, 'name': 'c'},
      ];
      expect(groupOrder(devicesTable(), rows), ['']);
    });
  });

  group('validation still applies to a list table', () {
    test('a bad cell is reported with its row number', () {
      final descriptor = ConfigDescriptor.fromJson({
        'plugin_id': 'plugin.caseta',
        'descriptor_version': 1,
        'sections': [
          {
            'id': 'devices',
            'title': 'Devices',
            'fields': [devicesTable().toJsonForTest()],
          }
        ],
      });
      final problems = documentProblems(descriptor: descriptor, values: {
        'devices': [
          {'integration_id': 2, 'kind': 'switch'},
          {'integration_id': 'nineteen'},
        ],
      });
      expect(
          problems, ['Devices row 2: Integration ID must be a whole number']);
    });
  });

  group('generated columns', () {
    List<CfgField> cols() => CfgField.fromJson({
          'key': 'thermostat',
          'kind': 'table',
          'item': [
            {'key': 'id', 'kind': 'text', 'generated': true},
            {'key': 'name', 'kind': 'text', 'prompt_when_empty': true},
            {'key': 'aggregation', 'kind': 'select', 'default': 'average'},
          ],
        }).itemFields!;

    test('a new row arrives with its generated id already set', () {
      // The operator never sees this column, so the row cannot be created
      // without one — an empty id would fail the plugin's own validation
      // ("thermostat id is required") on the very first save.
      final row = newRowFor(cols(), idSeed: 1234567);
      expect(row['id'], isNotEmpty);
      expect(row['name'], '');
      expect(row['aggregation'], 'average');
    });

    test('generated ids are opaque and distinct per row', () {
      final a = newRowFor(cols(), idSeed: 1)['id'];
      final b = newRowFor(cols(), idSeed: 2)['id'];
      expect(a, isNot(b));
      // Opaque on purpose: rules are written against the canonical name core
      // derives from the area and display name, so this must never carry
      // meaning that a rename could invalidate.
      expect(a, isNot(contains('thermostat')));
    });

    test('the flag is off unless the descriptor asks for it', () {
      final name = cols().firstWhere((c) => c.key == 'name');
      expect(name.generated, isFalse);
      expect(cols().firstWhere((c) => c.key == 'id').generated, isTrue);
    });
  });

  group('capability-filtered sources', () {
    CfgField sensors() => CfgField.fromJson({
          'key': 'sensor_device_ids',
          'kind': 'list',
          'item': 'text',
          'source': {
            'kind': 'core_resource',
            'ref': 'all_devices',
            'capability': 'temperature',
          },
        });

    test('a capability picks its own resolved list', () {
      // Sharing `all_devices` would hand the filtered picker the unfiltered
      // rows — every light in the house offered as a temperature sensor.
      expect(sensors().source!.dataKey, 'all_devices#temperature');
    });

    test('an unfiltered source keeps using the bare ref', () {
      final f = CfgField.fromJson({
        'key': 'x',
        'kind': 'select',
        'source': {'kind': 'core_resource', 'ref': 'areas'},
      });
      expect(f.source!.capability, isNull);
      expect(f.source!.dataKey, 'areas');
    });
  });
}

/// Round-trips a field back to JSON so a descriptor can be assembled from one.
extension on CfgField {
  Map<String, dynamic> toJsonForTest() => {
        'key': key,
        'kind': kind,
        'label': label,
        'render': render,
        'group_by': groupBy,
        'key_by': keyBy,
        'item': [
          for (final c in itemFields ?? const <CfgField>[])
            {
              'key': c.key,
              'kind': c.kind,
              'label': c.label,
              'prompt_when_empty': c.promptWhenEmpty,
              if (c.options != null)
                'options': [
                  for (final o in c.options!)
                    {'value': o.value, 'label': o.label}
                ],
            }
        ],
      };
}

/// hc-thermostat's sensor column: a `list` that declares a source, which is
/// what makes it a picker rather than a comma-separated text box.
CfgField sensorColumn() => CfgField.fromJson({
      'key': 'sensor_device_ids',
      'kind': 'list',
      'item': 'text',
      'label': 'Sensors',
      'source': {'kind': 'core_resource', 'ref': 'all_devices'},
    });

void _sourceBoundListColumnTests() {
  group('source-bound list column', () {
    test('a list column with a source is distinguishable from a plain one', () {
      // This is the whole switch in _columnControl: with a source it renders
      // the chips picker, without one a CSV text box. A thermostat's sensors
      // are references to other plugins' devices, which nobody can retype.
      final picker = sensorColumn();
      expect(picker.kind, 'list');
      expect(picker.source?.ref, 'all_devices');

      final plain = CfgField.fromJson({
        'key': 'buttons',
        'kind': 'list',
        'item': 'int',
      });
      expect(plain.source, isNull);
    });

    test('a list of device ids round-trips through the CSV representation', () {
      // _MultiSelect emits CSV and _coerceColumn parses it back, so the stored
      // value must end up a real JSON array — a string here would fail to
      // deserialize into Vec<String> and take the plugin offline on the
      // restart that saving triggers.
      final ids = ['zwave_12', 'ecowitt_outdoor_temp'];
      final csv = ids.join(', ');
      expect(splitCsv(csv), ids);
      expect(valueProblem(sensorColumn(), splitCsv(csv)), isNull);
      expect(valueProblem(sensorColumn(), csv), 'must be a list');
    });

    test('an id with no matching device is still a valid stored value', () {
      // A device can be removed while its id sits in a thermostat's sensor
      // list. The control shows the raw id rather than dropping the chip —
      // silently discarding it would edit the config by rendering it.
      expect(valueProblem(sensorColumn(), ['gone_device']), isNull);
    });
  });
}
