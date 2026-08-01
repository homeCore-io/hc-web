import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/plugins/config_descriptor/attention_banner.dart';
import 'package:hc_web/features/plugins/config_descriptor/descriptor.dart';

/// A row that is *wanted* but not *required* is invisible until something says
/// so.
///
/// Caséta is the case that proved it. A Lutron integration report carries no
/// load type, so every imported zone arrives with no Kind; the plugin skips
/// such a device at startup and logs a warning rather than failing to parse.
/// Nine rows went into the config, two devices came out, and the only
/// explanation was a `warn!` in a plugin log the UI could not display — so it
/// read as an import that lost devices.
///
/// `prompt_when_empty` already marked the column. The renderer already marked
/// individual rows. Neither helps when the complaint is that the devices are
/// not where you expected them, and you are not looking at the rows at all.
///
/// The Caséta devices table, as the plugin publishes it.
CfgField _devicesTable() => CfgField.fromJson({
      'key': 'devices',
      'kind': 'table',
      'label': 'Devices',
      'render': 'list',
      'key_by': 'integration_id',
      'item': [
        {'key': 'integration_id', 'kind': 'int', 'label': 'ID'},
        {'key': 'name', 'kind': 'text', 'label': 'Name'},
        {
          'key': 'kind',
          'kind': 'select',
          'label': 'Kind',
          'prompt_when_empty': true,
          'options': [
            {'value': 'dimmer', 'label': 'Dimmer'},
            {'value': 'switch', 'label': 'Switch'},
          ],
        },
      ],
    });

Widget _app(List<Map<String, dynamic>> devices) {
  final f = _devicesTable();
  final count = AttentionBanner.countNeedingAttention(f, devices);
  return MaterialApp(
    theme: hcTheme(HcSkin.midnight),
    home: Scaffold(
      body: count == 0
          ? const SizedBox.shrink()
          : AttentionBanner(field: f, count: count),
    ),
  );
}

void main() {
  testWidgets('rows missing a prompted column are announced above the table',
      (tester) async {
    await tester.pumpWidget(_app([
      {'integration_id': 2, 'name': 'Holiday Lights 1'},
      {'integration_id': 3, 'name': 'Holiday Lights 2'},
      {'integration_id': 6, 'name': 'Pico', 'kind': 'switch'},
    ]));
    await tester.pumpAndSettle();

    // Names the count and the column, from the descriptor — nothing in the
    // renderer knows what Caséta or a "Kind" is.
    expect(find.textContaining('2 devices need a Kind'), findsOneWidget);
    // And says what the consequence is, which is the part the operator was
    // missing: these rows exist in config but not in homeCore.
    expect(find.textContaining('do not appear in homeCore'), findsOneWidget);
  });

  testWidgets('a single row reads as one, not as "1 devices"', (tester) async {
    await tester.pumpWidget(_app([
      {'integration_id': 2, 'name': 'Holiday Lights 1'},
      {'integration_id': 6, 'name': 'Pico', 'kind': 'switch'},
    ]));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 device needs a Kind'), findsOneWidget);
  });

  testWidgets('no banner once every row has been classified', (tester) async {
    await tester.pumpWidget(_app([
      {'integration_id': 2, 'name': 'Holiday Lights 1', 'kind': 'dimmer'},
      {'integration_id': 6, 'name': 'Pico', 'kind': 'switch'},
    ]));
    await tester.pumpAndSettle();

    // It has to clear itself, or it becomes furniture people stop reading.
    expect(find.textContaining('need'), findsNothing);
  });

  testWidgets('an empty string counts as missing, not as a choice',
      (tester) async {
    // Config round-trips can turn an absent value into "", and a banner that
    // only checked for null would go quiet while the plugin still skipped the
    // row.
    await tester.pumpWidget(_app([
      {'integration_id': 2, 'name': 'Holiday Lights 1', 'kind': ''},
    ]));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 device needs a Kind'), findsOneWidget);
  });
}
