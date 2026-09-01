import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/plugin_render.dart';

void main() {
  group('reading a declaration', () {
    test('a node keeps its children and flattens everything else', () {
      final node = RenderNode.fromJson({
        'kind': 'row',
        'gap': 8,
        'children': [
          {'kind': 'gauge', 'value': 'flow', 'shape': 'radial'},
          {'kind': 'text', 'content': 'Flow'},
        ],
      })!;

      expect(node.kind, 'row');
      expect(node.isContainer, isTrue);
      // `kind` and `children` are structure; everything else is the
      // instrument's own, exactly as it arrives flattened on the wire.
      expect(node.fields, {'gap': 8});
      expect(node.children.map((c) => c.kind), ['gauge', 'text']);
      expect(node.children.first.fields['value'], 'flow');
    });

    test('a node with no kind is not a node', () {
      expect(RenderNode.fromJson(null), isNull);
      expect(RenderNode.fromJson('gauge'), isNull);
      expect(RenderNode.fromJson({'value': 'flow'}), isNull);
      expect(RenderNode.fromJson({'kind': ''}), isNull);
    });

    test('an unreadable child is dropped, not the whole tree', () {
      // Half a tree still draws something. The alternative is a card that
      // vanishes because one node in it was written by a newer core.
      final node = RenderNode.fromJson({
        'kind': 'column',
        'children': [
          {'kind': 'text', 'content': 'Flow'},
          'not a node',
          {'no_kind': true},
        ],
      })!;
      expect(node.children.map((c) => c.kind), ['text']);
    });

    test('a descriptor reads back whole', () {
      final spec = PluginWidgetSpec.fromJson({
        'plugin_id': 'boiler',
        'widget_id': 'boiler_flow',
        'title': 'Boiler flow',
        'icon': 'water',
        'bindings': [
          {
            'name': 'flow',
            'device': '{{config.device_id}}',
            'key': 'flow_lpm',
          }
        ],
        'render': {'kind': 'gauge', 'value': 'flow'},
      })!;

      expect(spec.pluginId, 'boiler');
      expect(spec.title, 'Boiler flow');
      expect(spec.render!.kind, 'gauge');
      expect(spec.binding('flow')!.key, 'flow_lpm');
      expect(spec.binding('nothing'), isNull);
    });

    test('a widget with no title falls back to its id, never to nothing', () {
      final spec = PluginWidgetSpec.fromJson({
        'plugin_id': 'boiler',
        'widget_id': 'boiler_flow',
        'render': {'kind': 'gauge', 'value': 'flow'},
      })!;
      expect(spec.title, 'boiler_flow');
    });
  });

  group('resolving which device a binding reads', () {
    const templated = PluginBinding(
      name: 'flow',
      device: '{{config.device_id}}',
      key: 'flow_lpm',
    );

    test('a template resolves against the card that was placed', () {
      // The declaration is written once and the card is placed many times, so
      // the device is whichever one this card was pointed at.
      expect(templated.resolveDevice({'device_id': 'boiler_1'}), 'boiler_1');
    });

    test('an unfilled template resolves to nothing, not to itself', () {
      // Returning the literal `{{config.device_id}}` would send the client
      // looking for a device by that name and report "not here", which blames
      // the house for a card nobody finished configuring.
      expect(templated.resolveDevice({}), isNull);
      expect(templated.resolveDevice({'device_id': ''}), isNull);
    });

    test('a literal device id is used as written', () {
      const fixed =
          PluginBinding(name: 'flow', device: 'boiler_1', key: 'flow_lpm');
      expect(fixed.resolveDevice(const {}), 'boiler_1');
    });

    test('a template inside a longer string is not a template', () {
      // Not a substitution language. A device id is an identifier, never a
      // sentence with a value in the middle, so this is a typo far more often
      // than it is an intention — and treating it as one would look up a
      // device whose id is half a template.
      const odd = PluginBinding(
        name: 'flow',
        device: 'boiler_{{config.device_id}}',
        key: 'flow_lpm',
      );
      expect(odd.resolveDevice({'device_id': '1'}), 'boiler_{{config.device_id}}');
    });
  });

  group('mapping a reading onto an instrument', () {
    PluginBinding ranged(double from, double to) => PluginBinding(
          name: 'flow',
          device: 'boiler_1',
          key: 'flow_lpm',
          inFrom: from,
          inTo: to,
          outFrom: 0,
          outTo: 1,
        );

    test('without a range the value passes through', () {
      const plain =
          PluginBinding(name: 'flow', device: 'boiler_1', key: 'flow_lpm');
      expect(plain.hasRange, isFalse);
      expect(plain.map(21.5), 21.5);
    });

    test('a range maps the ends and the middle', () {
      final b = ranged(0, 30);
      expect(b.hasRange, isTrue);
      expect(b.map(0), 0);
      expect(b.map(30), 1);
      expect(b.map(15), 0.5);
    });

    test('a value outside the range is not clamped here', () {
      // Mapping is arithmetic; deciding what an over-range reading looks like
      // belongs to the instrument, which is the only thing that knows whether
      // it can draw past full.
      expect(ranged(0, 30).map(45), 1.5);
    });

    test('a zero-width range answers the bottom rather than infinity', () {
      // Every input is equally the minimum. Dividing would answer infinity and
      // draw a full gauge for a reading that means nothing.
      expect(ranged(10, 10).map(10), 0);
      expect(ranged(10, 10).map(99), 0);
    });

    test('nothing in, nothing out', () {
      expect(ranged(0, 30).map(null), isNull);
    });

    test('three of four bounds is not a range', () {
      // Core rejects this at registration, so it is not a case to survive
      // gracefully — only one to refuse to misread as a working mapping.
      const partial = PluginBinding(
        name: 'flow',
        device: 'boiler_1',
        key: 'flow_lpm',
        inFrom: 0,
        inTo: 30,
        outFrom: 0,
      );
      expect(partial.hasRange, isFalse);
      expect(partial.map(15), 15);
    });
  });
}
