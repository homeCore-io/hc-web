import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/providers/automations_provider.dart';
import 'package:hc_web/core/rules/node.dart';
import 'package:hc_web/core/rules/rule.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/design/tokens.dart';
import 'package:hc_web/features/automations/automation_editor_page.dart';

HcRule _rule({List<String> tags = const []}) => HcRule(
      id: 'r1',
      name: 'Door Alert',
      trigger: HcNode('ManualTrigger'),
      tags: [...tags],
    );

Widget _host(HcRule rule, List<HcRule> all, {VoidCallback? onChanged}) =>
    ProviderScope(
      overrides: [
        automationsProvider.overrideWith(() => _StubAutomations(all)),
      ],
      child: MaterialApp(
        theme: hcTheme(HcSkin.midnight),
        home: Scaffold(
          body: RuleMetaLineTestAccess(
            rule: rule,
            onChanged: onChanged ?? () {},
          ),
        ),
      ),
    );

class _StubAutomations extends AutomationsNotifier {
  _StubAutomations(this._rules);
  final List<HcRule> _rules;
  @override
  Future<List<HcRule>> build() async => _rules;
}

void main() {
  group('a rule can be tagged from the editor', () {
    testWidgets('an untagged rule offers to add one', (tester) async {
      // Tags existed end to end — core stores them, the list groups by them —
      // with nothing anywhere to set one. 30 of 34 rules sat under "Untagged"
      // because tagging meant hand-editing a RON file.
      await tester.pumpWidget(_host(_rule(), []));
      await tester.pumpAndSettle();
      expect(find.text('add a tag'), findsOneWidget);
    });

    testWidgets('a tag chip is marked as a tag, not as another setting',
        (tester) async {
      // `deck` sitting after `run in parallel` is indistinguishable from a
      // setting without one.
      await tester.pumpWidget(_host(_rule(tags: ['deck']), []));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.local_offer_outlined), findsOneWidget);

      // And it carries the accent the list gives a tag group, rather than the
      // grey every setting chip uses.
      final label = tester.widget<Text>(find.text('deck'));
      final muted =
          HcTokens.of(tester.element(find.text('deck'))).surface.onBaseMuted;
      expect(label.style?.color, isNot(muted));
    });

    testWidgets('each tag is its own chip, removable in one tap',
        (tester) async {
      final rule = _rule(tags: ['deck', 'garage']);
      var changed = 0;
      await tester.pumpWidget(_host(rule, [], onChanged: () => changed++));
      await tester.pumpAndSettle();

      expect(find.text('deck'), findsOneWidget);
      expect(find.text('garage'), findsOneWidget);

      await tester.tap(find.text('deck'));
      await tester.pumpAndSettle();

      expect(rule.tags, ['garage']);
      expect(changed, 1);
    });

    testWidgets('tags already in use are offered, so spellings converge',
        (tester) async {
      // A free text box produces "deck", "Deck" and "decks" within a week, and
      // then the grouping stops grouping.
      final rule = _rule();
      await tester.pumpWidget(_host(rule, [
        _rule(tags: ['deck']),
        _rule(tags: ['vacation', 'deck']),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('add a tag'));
      await tester.pumpAndSettle();

      // RailLabel uppercases, like every other non-input label in the editor.
      expect(
          find.textContaining(RegExp('already in use', caseSensitive: false)),
          findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, 'vacation'));
      await tester.pumpAndSettle();

      expect(rule.tags, ['vacation']);
    });

    testWidgets('a tag the rule already has is not offered twice',
        (tester) async {
      final rule = _rule(tags: ['deck']);
      await tester.pumpWidget(_host(rule, [
        _rule(tags: ['deck', 'garage']),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('add'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ActionChip, 'garage'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'deck'), findsNothing);
    });
  });
}
