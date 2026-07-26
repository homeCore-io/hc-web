import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/automations/widgets/device_picker_shell.dart';

Widget _panel({VoidCallback? onPrimary}) => MaterialApp(
      theme: hcTheme(HcSkin.midnight),
      home: Builder(
        builder: (context) => Scaffold(
          body: PickerPanel(
            kicker: 'Then',
            title: 'What should happen?',
            seg: const SizedBox.shrink(),
            footerHint: 'a hint',
            primaryLabel: 'Add action',
            onPrimary: onPrimary ?? () {},
            panes: const [
              PickerPane(
                  width: 202,
                  compactLabel: 'Where',
                  child: Center(child: Text('RAIL'))),
              PickerPane(
                  compactLabel: 'What', child: Center(child: Text('LIST'))),
              PickerPane(
                  compactLabel: 'Details',
                  child: Center(child: Text('DETAIL'))),
            ],
          ),
        ),
      ),
    );

void main() {
  group('the picker fits the viewport it is given', () {
    testWidgets('a desktop shows every pane at once', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_panel());
      await tester.pumpAndSettle();

      expect(find.text('RAIL'), findsOneWidget);
      expect(find.text('LIST'), findsOneWidget);
      expect(find.text('DETAIL'), findsOneWidget);
      expect(find.text('Add action'), findsOneWidget);
    });

    testWidgets('a short window does not clip the footer', (tester) async {
      // The failure this prevents: a fixed 470px pane block plus header and
      // footer overflowed anything under ~620px tall, and an overflowing
      // dialog clips its own footer — so the primary button, the only way to
      // commit, became unreachable.
      await tester.binding.setSurfaceSize(const Size(1200, 560));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_panel());
      await tester.pumpAndSettle();

      expect(find.text('Add action'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow');
    });

    testWidgets('a phone shows one step at a time', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_panel());
      await tester.pumpAndSettle();

      // Three panes side by side on a 390px screen is three unusable columns.
      expect(find.text('RAIL'), findsOneWidget);
      expect(find.text('LIST'), findsNothing);
      expect(find.text('DETAIL'), findsNothing);

      // The primary advances rather than committing, so a half-made choice
      // cannot be submitted by the button that means "next".
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Add action'), findsNothing);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('LIST'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('DETAIL'), findsOneWidget);
      // Only the last step commits.
      expect(find.text('Add action'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
    });

    testWidgets('a passed step can be revisited from the step bar',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_panel());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Where'));
      await tester.pumpAndSettle();
      expect(find.text('RAIL'), findsOneWidget);
    });
  });
}
