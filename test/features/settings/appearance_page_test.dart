import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/providers/skin_provider.dart';
import 'package:hc_web/design/skin_resolve.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/design/tokens.dart';
import 'package:hc_web/features/settings/appearance_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The picker, end to end: tap a skin, the app is in it, and it is still in it
/// after a reload.
///
/// Worth testing through the widget rather than through the provider, because
/// the provider was already correct and unreachable — the thing that was
/// missing for the whole life of the skin system was a way to press it.

/// Renders whatever skin is currently resolved, so a tap can be checked by
/// what the app looks like rather than by what the provider holds.
class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) =>
      Text('skin=${HcTokens.of(context).name}');
}

Widget _host() => ProviderScope(
      child: Consumer(
        builder: (context, ref, _) {
          // Stands in for ShellScope: the app's skin, applied above the page.
          final tokens = resolveSkin(
            choice: ref.watch(skinOverrideProvider),
            shell: HcShell.touch,
            skins: const [],
          );
          return MaterialApp(
            theme: hcThemeFromTokens(tokens),
            home: const Column(
              children: [
                _Probe(),
                Expanded(child: AppearancePage()),
              ],
            ),
          );
        },
      ),
    );

/// Opens the page on a viewport tall enough to hold all five options.
///
/// Five cards, each with a preview and two lines of copy, do not fit the
/// 800x600 default — and an option scrolled out of view is not an option that
/// is missing, so without this a failure would say the wrong thing.
Future<void> _open(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_host());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('it offers every skin, plus following the surface',
      (tester) async {
    await _open(tester);

    expect(find.text('Follow the surface'), findsOneWidget);
    for (final skin in HcSkin.values) {
      expect(find.text(skin.label), findsOneWidget,
          reason: '${skin.name} is not offered');
    }
  });

  testWidgets('picking a skin re-skins the app', (tester) async {
    await _open(tester);
    expect(find.text('skin=midnight'), findsOneWidget);

    await tester.tap(find.text('Soft Home'));
    await tester.pumpAndSettle();

    expect(find.text('skin=soft_home'), findsOneWidget,
        reason: 'the choice did not reach the app');
  });

  testWidgets('the choice survives a reload', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Control Room'));
    await tester.pumpAndSettle();

    // A fresh ProviderScope is a fresh page load; the preference has to come
    // back out of storage on its own.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('skin=control_room'), findsOneWidget,
        reason: 'the reload lost the chosen skin');
  });

  testWidgets('following the surface is selectable again after a choice',
      (tester) async {
    await _open(tester);
    await tester.tap(find.text('Soft Home'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Follow the surface'));
    await tester.pumpAndSettle();

    // Back to the shell's own default, and nothing left in storage.
    expect(find.text('skin=midnight'), findsOneWidget);
    final store = await SharedPreferences.getInstance();
    expect(store.getKeys().contains('skin'), isFalse);
  });

  testWidgets('the selected option is the one that is marked', (tester) async {
    await _open(tester);
    // Nothing chosen: "Follow the surface" is the selection.
    expect(
      tester.widgetList<Icon>(find.byIcon(Icons.radio_button_checked)).length,
      1,
    );

    await tester.tap(find.text('Ambient Glass'));
    await tester.pumpAndSettle();
    expect(
      tester.widgetList<Icon>(find.byIcon(Icons.radio_button_checked)).length,
      1,
      reason: 'two options claimed to be selected at once',
    );
  });
}
