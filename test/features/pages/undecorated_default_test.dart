import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/card_style.dart';

/// What a new element wears, and what an old one keeps wearing.
///
/// Two facts that have to be true at once, and the whole change is the gap
/// between them: **absent means a card** (so nothing saved changes) while
/// **new means nothing** (so designing does not start by undoing sixteen
/// pixels of border on every element you place).
///
/// The three creation sites in the designer — the catalogue, the devices rail
/// and the assets rail — write the second one explicitly at the moment they
/// make an element. That is what makes this a difference between documents
/// rather than between versions of the reader, which is the only version of
/// this change that is safe to ship.
void main() {
  group('a page that predates this', () {
    test('reads as a card, exactly as it did', () {
      const style = CardStyle();
      expect(CardStyle.fromConfig(const {}), isNotNull);
      final read = CardStyle.fromConfig(const {'device_id': 'lamp'});
      expect(read.filled, isTrue);
      expect(read.bordered, isTrue);
      expect(read.titled, isTrue);
      expect(read.isDefault, isTrue);
      expect(style.isDefault, isTrue);
    });

    test('and writing it back adds no key', () {
      // The rule that keeps a document from growing by being opened.
      expect(const CardStyle().toConfig(const {'device_id': 'lamp'}),
          {'device_id': 'lamp'});
    });
  });

  group('an element made today', () {
    test('wears nothing', () {
      expect(CardStyle.undecorated.filled, isFalse);
      expect(CardStyle.undecorated.bordered, isFalse);
      expect(CardStyle.undecorated.titled, isFalse);
      expect(CardStyle.undecorated.isDefault, isFalse,
          reason: 'or it would write nothing and read back as a card');
    });

    test('says so in the document, beside whatever else it carries', () {
      final config = CardStyle.undecorated.toConfig({'device_id': 'lamp'});
      expect(config['device_id'], 'lamp');
      expect(config[CardStyle.key],
          {'filled': false, 'bordered': false, 'titled': false});
    });

    test('survives the round trip', () {
      final back =
          CardStyle.fromConfig(CardStyle.undecorated.toConfig(const {}));
      expect(back.filled, isFalse);
      expect(back.bordered, isFalse);
      expect(back.titled, isFalse);
    });

    test('keeps nothing else from being said', () {
      // The undecorated style is a starting point, not a mode: everything the
      // style pane offers still applies on top of it.
      final styled = CardStyle.undecorated
          .copyWith(filled: true, tint: 'accent', corner: 'lg');
      final back = CardStyle.fromConfig(styled.toConfig(const {}));
      expect(back.filled, isTrue);
      expect(back.bordered, isFalse, reason: 'still no outline');
      expect(back.tint, 'accent');
      expect(back.corner, 'lg');
    });
  });

  group('the two presets are the two ends', () {
    test('Card turns all three on and is then the default', () {
      final card = CardStyle.undecorated
          .copyWith(filled: true, bordered: true, titled: true);
      expect(card.isDefault, isTrue,
          reason: 'so pressing Card writes no style key at all');
    });

    test('Plain turns all three off', () {
      const card = CardStyle();
      final plain =
          card.copyWith(filled: false, bordered: false, titled: false);
      expect(plain, CardStyle.undecorated);
    });
  });
}
