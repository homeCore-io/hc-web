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
      expect(needsAttention(t, {'integration_id': 2, 'kind': 'switch'}), isFalse);
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
      expect(problems, ['Devices row 2: Integration ID must be a whole number']);
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
