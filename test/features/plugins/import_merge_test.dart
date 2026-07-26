import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/features/plugins/config_descriptor/import_merge.dart';

/// Two Lutron devices as they sit in a config imported before the plugin
/// learned about buttons.
List<Map<String, dynamic>> configured() => [
      {'integration_id': 51, 'name': 'Outside Lights', 'kind': 'pico'},
      {'integration_id': 60, 'name': 'Hallway 6 Button', 'kind': 'keypad'},
    ];

void main() {
  group('re-importing a design', () {
    test('fills new details into rows that already exist', () {
      // The bug this exists for: every row was a duplicate, so an import that
      // could only append reported "completed" and changed nothing. Buttons
      // never reached a config that had been imported once already.
      final rows = configured();
      final outcome = mergeImportedRows(
          rows,
          [
            {
              'integration_id': 51,
              'name': 'Outside Lights',
              'kind': 'pico',
              'all_buttons': [2, 4],
              'button_names': ['Outside On', 'Outside Off'],
            },
          ],
          'integration_id');

      expect(outcome.added, 0);
      expect(outcome.updated, 1);
      expect(outcome.skipped, 0);
      expect(rows.first['all_buttons'], [2, 4]);
      expect(rows.first['button_names'], ['Outside On', 'Outside Off']);
    });

    test('never overwrites a value already there', () {
      // A name may have been edited by hand. An import is not entitled to
      // undo that just because the repeater disagrees.
      final rows = configured();
      rows.first['name'] = 'Patio Pico';
      final outcome = mergeImportedRows(
          rows,
          [
            {
              'integration_id': 51,
              'name': 'Outside Lights',
              'all_buttons': [2, 4]
            },
          ],
          'integration_id');

      expect(rows.first['name'], 'Patio Pico',
          reason: 'the hand edit survives');
      expect(rows.first['all_buttons'], [2, 4], reason: 'the new key lands');
      expect(outcome.updated, 1);
    });

    test('a row with nothing new to say is skipped, not counted as updated',
        () {
      final rows = configured();
      final outcome = mergeImportedRows(
          rows,
          [
            {
              'integration_id': 60,
              'name': 'Hallway 6 Button',
              'kind': 'keypad'
            },
          ],
          'integration_id');

      expect(outcome.skipped, 1);
      expect(outcome.updated, 0);
      expect(outcome.added, 0);
    });

    test('genuinely new rows are still appended', () {
      final rows = configured();
      final outcome = mergeImportedRows(
          rows,
          [
            {'integration_id': 99, 'name': 'New Pico', 'kind': 'pico'},
          ],
          'integration_id');

      expect(outcome.added, 1);
      expect(rows, hasLength(3));
    });

    test('mixed batches report each outcome separately', () {
      final rows = configured();
      final outcome = mergeImportedRows(
          rows,
          [
            {
              'integration_id': 51,
              'all_buttons': [2, 4]
            }, // enriched
            {'integration_id': 60, 'name': 'Hallway 6 Button'}, // nothing new
            {'integration_id': 99, 'name': 'New Pico'}, // added
          ],
          'integration_id');

      expect(outcome.updated, 1);
      expect(outcome.skipped, 1);
      expect(outcome.added, 1);
    });

    test('without a key every row is appended, as before', () {
      // A table with no `key_by` has no identity to match on, so the only
      // honest behaviour is to append.
      final rows = configured();
      final outcome = mergeImportedRows(
          rows,
          [
            {'name': 'Outside Lights'},
          ],
          null);

      expect(outcome.added, 1);
      expect(rows, hasLength(3));
    });

    test('non-map entries are ignored rather than throwing', () {
      final rows = configured();
      final outcome =
          mergeImportedRows(rows, ['nonsense', null], 'integration_id');
      expect(outcome.added, 0);
      expect(rows, hasLength(2));
    });
  });
}
