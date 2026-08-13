import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/code_runtime.dart';
import 'package:hc_web/core/models/device_state.dart';

/// The rules a code element cannot be allowed to lose quietly.
///
/// A regression here does not look like a broken card — it looks like a working
/// card with a hole in it, which is why these are asserted on the strings
/// themselves rather than on a rendered frame.
void main() {
  DeviceState device(String id, {Map<String, dynamic>? state}) => DeviceState(
        id: id,
        pluginId: 'test',
        name: 'Lamp $id',
        area: 'living_room',
        deviceType: 'light',
        available: true,
        state: state ?? {'on': true, 'brightness': 200},
        lastSeen: DateTime.utc(2026, 8, 13),
      );

  group('the sandbox', () {
    test('never grants same-origin', () {
      // The one combination that would undo everything: a frame with both
      // flags can remove its own sandbox attribute.
      expect(codeSandbox, 'allow-scripts');
      expect(codeSandbox.contains('allow-same-origin'), isFalse);
    });

    test('closes the network by default', () {
      final csp = codeCsp(allowNetwork: false);
      expect(csp, contains("default-src 'none'"));
      expect(csp, isNot(contains('connect-src')));
      expect(csp, isNot(contains('https:')));
    });

    test('opens it only when asked, and never to remote script', () {
      final csp = codeCsp(allowNetwork: true);
      expect(csp, contains('connect-src'));
      // Even with the network open, script stays inline-only: no card can pull
      // in code from an address.
      expect(csp, contains("script-src 'unsafe-inline'"));
      expect(csp, isNot(contains('script-src https:')));
    });

    test('lets this house\'s own uploads through, and no other origin', () {
      final csp =
          codeCsp(allowNetwork: false, assetOrigin: 'http://10.0.10.150:8080');
      expect(csp, contains('img-src data: blob: http://10.0.10.150:8080'));
    });
  });

  group('the document', () {
    test('carries the policy, the shim and the author\'s markup', () {
      final doc = buildCodeDocument(
        html: '<div id="mine">hello</div>',
        cssVars: {'--hc-accent': '#ffb661'},
        nonce: 'abc123',
      );
      expect(doc, contains('Content-Security-Policy'));
      expect(doc, contains('window.homecore'));
      expect(doc, contains('<div id="mine">hello</div>'));
      expect(doc, contains('--hc-accent: #ffb661;'));
    });

    test('is transparent, so the page shows through', () {
      final doc =
          buildCodeDocument(html: '', cssVars: const {}, nonce: 'abc123');
      expect(doc, contains('background: transparent'));
    });
  });

  group('the state message', () {
    test('carries only the granted devices', () {
      final message = codeStateMessage([device('a'), device('b')], 'n1');
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      expect(decoded['type'], 'state');
      expect((decoded['states'] as Map).keys, ['a', 'b']);
    });

    test('narrows a device to what an author reads', () {
      final view = codeDeviceView(device('a'));
      expect(view['id'], 'a');
      expect(view['name'], 'Lamp a');
      expect(view['state'], {'on': true, 'brightness': 200});
      // The app's own bookkeeping stays this side of the boundary.
      expect(view.containsKey('schema'), isFalse);
      expect(view.containsKey('plugin_id'), isFalse);
    });
  });

  group('the nonce', () {
    // The bug this replaced: the sender was checked by comparing
    // `event.source` with the iframe's `contentWindow`, which across interop
    // compares wrappers rather than windows. It answered "different" for the
    // same window, so every message was dropped — including the handshake —
    // and a card drew its starting markup and then never heard from the house
    // again. Caught on screen, not by a test, which is why these exist.
    test('is required on the way in', () {
      final good = jsonEncode({'hc': 1, 'n': 'right', 'type': 'hello'});
      expect(parseCodeMessage(good, 'right'), isA<CodeHello>());
      expect(parseCodeMessage(good, 'other'), isNull);
      expect(parseCodeMessage(jsonEncode({'hc': 1, 'type': 'hello'}), 'right'),
          isNull);
    });

    test('is stamped on the way out, in both the document and the state', () {
      final doc = buildCodeDocument(html: '', cssVars: const {}, nonce: 'n42');
      expect(doc, contains("var NONCE = 'n42'"));
      // …and never the placeholder, which would make every frame share one.
      expect(doc, isNot(contains('__HC_NONCE__')));
      expect(codeStateMessage(const [], 'n42'), contains('"n":"n42"'));
    });

    test('is not guessable, and differs per element', () {
      final a = codeNonce();
      final b = codeNonce();
      expect(a, hasLength(32));
      expect(a, isNot(b));
    });
  });

  group('messages from the frame', () {
    test('a set is understood', () {
      final message = parseCodeMessage(
          jsonEncode({
            'hc': 1,
            'n': 'n1',
            'type': 'set',
            'id': 'a',
            'patch': {'on': false}
          }),
          'n1');
      expect(message, isA<CodeSet>());
      expect((message as CodeSet).id, 'a');
      expect(message.patch, {'on': false});
    });

    test('a log is understood', () {
      final message = parseCodeMessage(
          jsonEncode({'hc': 1, 'n': 'n1', 'type': 'log', 'text': 'hi'}), 'n1');
      expect((message as CodeLog).text, 'hi');
    });

    test('anything else is nothing', () {
      // Every other frame, extension and library shares this window, so the
      // parser has to reject far more than it accepts.
      expect(parseCodeMessage('not json', 'n1'), isNull);
      expect(parseCodeMessage(jsonEncode({'type': 'set', 'id': 'a'}), 'n1'),
          isNull);
      expect(
          parseCodeMessage(
              jsonEncode(
                  {'hc': 2, 'n': 'n1', 'type': 'set', 'id': 'a', 'patch': {}}),
              'n1'),
          isNull);
      expect(
          parseCodeMessage(
              jsonEncode({'hc': 1, 'n': 'n1', 'type': 'evaluate'}), 'n1'),
          isNull);
      expect(parseCodeMessage(42, 'n1'), isNull);
      expect(parseCodeMessage(null, 'n1'), isNull);
    });

    test('a set with no device is refused before it reaches the grant check',
        () {
      expect(
          parseCodeMessage(
              jsonEncode({
                'hc': 1,
                'n': 'n1',
                'type': 'set',
                'id': '',
                'patch': {'on': true}
              }),
              'n1'),
          isNull);
      expect(
          parseCodeMessage(
              jsonEncode({
                'hc': 1,
                'n': 'n1',
                'type': 'set',
                'id': 'a',
                'patch': 'on'
              }),
              'n1'),
          isNull);
    });
  });
}
