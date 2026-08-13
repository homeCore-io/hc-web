import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/svg_bindings.dart';

/// A drawing wired to the house: what a binding means, and what the generated
/// script is allowed to contain.
void main() {
  group('reading the drawing', () {
    test('lists the ids in the order they were drawn', () {
      const svg = '''
<svg><circle id="track"/><circle id="dial"/><text id="readout">--</text></svg>''';
      // Not sorted: ids come out in the order the artwork was built, which is
      // the order the person who built it remembers them in.
      expect(svgElementIds(svg), ['track', 'dial', 'readout']);
    });

    test('copes with single quotes, spacing and duplicates', () {
      const svg = "<g id = 'a'><g id=\"b\"/><g id='a'/></g>";
      expect(svgElementIds(svg), ['a', 'b']);
    });

    test('finds nothing in a drawing with no ids', () {
      expect(svgElementIds('<svg><circle r="4"/></svg>'), isEmpty);
    });

    test('the starter is bindable out of the box', () {
      // The first question a new drawing raises is "what do I bind to?", so the
      // starter has to answer it.
      expect(svgElementIds(svgStarter), contains('dial'));
      expect(svgElementIds(svgStarter), contains('readout'));
    });
  });

  group('a binding', () {
    test('round-trips through the document', () {
      const binding = SvgBinding(
        elementId: 'dial',
        attribute: 'stroke-dashoffset',
        deviceId: 'sensor_1',
        key: 'speed',
        inFrom: 0,
        inTo: 4,
        outFrom: 440,
        outTo: 160,
      );
      expect(SvgBinding.fromJson(binding.toJson()).toJson(), binding.toJson());
    });

    test('writes no key it does not need', () {
      const bare = SvgBinding(
        elementId: 'readout',
        attribute: 'text',
        deviceId: 'sensor_1',
        key: 'speed',
      );
      expect(bare.toJson().keys, ['id', 'attr', 'device', 'key']);
    });

    test('knows when it is not finished', () {
      const half = SvgBinding(
        elementId: 'dial',
        attribute: 'stroke-dashoffset',
        deviceId: '',
        key: '',
      );
      expect(half.isComplete, isFalse);
      expect(half.hasRange, isFalse);
    });

    test('clears from the config entirely when the last one goes', () {
      final config = bindingsToConfig(const {'svg': '<svg/>'}, const []);
      expect(config.containsKey('bindings'), isFalse);
      expect(config, {'svg': '<svg/>'});
    });
  });

  group('editing a binding', () {
    // Both of these were written while chasing a range that would not stick.
    test('successive edits accumulate when the config is fed back', () {
      var config = <String, dynamic>{
        'bindings': [
          {'id': 'dial', 'attr': 'opacity', 'device': 'd1', 'key': 'battery'}
        ],
      };
      void edit(SvgBinding Function(SvgBinding) change) {
        config = bindingsToConfig(
            config, [for (final b in bindingsFromConfig(config)) change(b)]);
      }

      edit((c) => c.copyWith(inFrom: 10.0));
      edit((c) => c.copyWith(inTo: 90.0));
      edit((c) => c.copyWith(outFrom: 217.0));
      edit((c) => c.copyWith(outTo: 40.0));

      expect(bindingsFromConfig(config).single.hasRange, isTrue);
    });

    test('and are lost when it is not — the editor must feed it back', () {
      const stale = <String, dynamic>{
        'bindings': [
          {'id': 'dial', 'attr': 'opacity', 'device': 'd1', 'key': 'battery'}
        ],
      };
      Map<String, dynamic> from(SvgBinding Function(SvgBinding) change) =>
          bindingsToConfig(
              stale, [for (final b in bindingsFromConfig(stale)) change(b)]);

      from((c) => c.copyWith(inFrom: 10.0));
      final last = from((c) => c.copyWith(outTo: 40.0));
      expect(bindingsFromConfig(last).single.inFrom, isNull);
    });

    test('a whole number does not blow up the write', () {
      // `copyWith`'s sentinel parameters are `Object?`, so nothing static stops
      // a caller passing an int. It used to throw inside `onChanged`, which
      // aborted the edit and left the field showing a value the document never
      // got.
      expect(
          () => const SvgBinding(
                  elementId: 'a', attribute: 'opacity', deviceId: 'd', key: 'k')
              .copyWith(inFrom: 10),
          returnsNormally);
      expect(
          const SvgBinding(
                  elementId: 'a', attribute: 'opacity', deviceId: 'd', key: 'k')
              .copyWith(inFrom: 10)
              .inFrom,
          10.0);
    });
  });

  group('the mapping', () {
    test('moves a reading onto the attribute\'s range', () {
      expect(mapValue(2, 0, 4, 440, 160), 300);
      expect(mapValue(0, 0, 4, 440, 160), 440);
      expect(mapValue(4, 0, 4, 440, 160), 160);
    });

    test('clamps, so an arc cannot draw a second lap', () {
      expect(mapValue(9, 0, 4, 440, 160), 160);
      expect(mapValue(-9, 0, 4, 440, 160), 440);
    });

    test('a range of zero is the start, not a division by it', () {
      expect(mapValue(5, 3, 3, 10, 20), 10);
    });
  });

  group('the generated script', () {
    test('carries only the bindings that could do something', () {
      final script = buildBinderScript(const [
        SvgBinding(
            elementId: 'dial',
            attribute: 'stroke-dashoffset',
            deviceId: 'd1',
            key: 'speed'),
        SvgBinding(
            elementId: 'half', attribute: 'opacity', deviceId: '', key: ''),
      ]);
      expect(script, contains('"id":"dial"'));
      expect(script, isNot(contains('"id":"half"')),
          reason: 'an unfinished row must not reach the drawing');
    });

    test('reads the same feed a code element does', () {
      final script = buildBinderScript(const []);
      expect(script, contains('homecore.onUpdate'));
      // Whoever outgrows the editor opens the same drawing as a code element
      // and finds nothing surprising in it.
      expect(script, isNot(contains('eval')));
    });

    test('says so when a binding points at nothing', () {
      // A drawing that silently does nothing is the worst outcome here, so
      // every miss goes to the console the editor shows.
      final script = buildBinderScript(const [
        SvgBinding(
            elementId: 'gone', attribute: 'opacity', deviceId: 'd1', key: 'x'),
      ]);
      expect(script, contains('homecore.log'));
      expect(script, contains('No element #'));
    });

    test('escapes what it embeds', () {
      // The id comes from a file somebody downloaded; it reaches the script as
      // JSON, never as concatenated source.
      final script = buildBinderScript(const [
        SvgBinding(
            elementId: 'a"];alert(1);//',
            attribute: 'opacity',
            deviceId: 'd1',
            key: 'x'),
      ]);
      // The dangerous shape is a quote that closes the JSON string early and
      // leaves the rest as code. Escaped, it cannot: what appears is
      // `"id":"a\"];…`, never `"id":"a"];…`.
      expect(script, isNot(contains('"id":"a"]')));
      expect(script, contains(jsonEncode('a"];alert(1);//')));
    });
  });

  group('the body', () {
    test('is the drawing followed by its wiring', () {
      final body = buildSvgBody('<svg id="art"/>', const [
        SvgBinding(
            elementId: 'art', attribute: 'opacity', deviceId: 'd1', key: 'x'),
      ]);
      expect(
          body.indexOf('<svg id="art"/>'), lessThan(body.indexOf('<script>')));
    });
  });
}
