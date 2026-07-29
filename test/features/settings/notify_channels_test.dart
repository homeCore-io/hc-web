import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/features/settings/notify_channels.dart';

void main() {
  group('reading the block out of the config', () {
    test('a house with no channels has none, not an error', () {
      // The common case: `[[notify.channels]]` has never been written, so
      // `notify` is absent from the parsed file entirely.
      expect(channelsFrom(const {}), isEmpty);
      expect(channelsFrom(const {'notify': {}}), isEmpty);
      expect(
          channelsFrom(const {
            'server': {'port': 8080}
          }),
          isEmpty);
    });

    test('a flat row splits into name, type and provider fields', () {
      // Core flattens the provider into the row — `#[serde(flatten)]` — so
      // there is no nesting to unwrap here, and `type` is the tag.
      final channels = channelsFrom(const {
        'notify': {
          'channels': [
            {
              'name': 'leaks',
              'type': 'email',
              'smtp_host': 'smtp.example.com',
              'smtp_port': 587,
              'username': 'house',
              'password': 'hunter2',
              'from': 'house@example.com',
              'to': ['john@example.com'],
              'starttls': true,
            }
          ]
        }
      });

      expect(channels.length, 1);
      final c = channels.single;
      expect(c.name, 'leaks');
      expect(c.type, 'email');
      expect(c.values['smtp_port'], 587);
      expect(c.values.containsKey('name'), isFalse,
          reason: 'name is the channel, not a provider field');
      expect(c.values.containsKey('type'), isFalse);
    });

    test('a provider this client has never heard of still lists', () {
      // Core may gain a provider before the client does. Showing the row and
      // saying so beats hiding a channel that exists and works.
      final c = channelsFrom(const {
        'notify': {
          'channels': [
            {'name': 'ntfy', 'type': 'ntfy', 'topic': 'house'}
          ]
        }
      }).single;
      expect(c.name, 'ntfy');
      expect(c.kind, isNull);
      expect(c.values['topic'], 'house');
    });
  });

  group('writing it back', () {
    test('round-trips flat, the way core reads it', () {
      const row = {
        'name': 'phone',
        'type': 'pushover',
        'api_token': 'tok',
        'user_key': 'usr',
      };
      final c = channelsFrom(const {
        'notify': {
          'channels': [row]
        }
      }).single;

      // The array-of-tables write replaces the block wholesale, so what goes
      // back has to be exactly what came out — any key dropped here is a key
      // deleted from the file.
      expect(c.toToml(), row);
    });

    test('an unknown provider survives a round trip untouched', () {
      const row = {'name': 'ntfy', 'type': 'ntfy', 'topic': 'house'};
      final c = channelsFrom(const {
        'notify': {
          'channels': [row]
        }
      }).single;
      expect(c.toToml(), row,
          reason: 'editing channel A must not corrupt channel B');
    });
  });

  group('validation', () {
    NotifyChannel email({String name = 'ok'}) => NotifyChannel(
          name: name,
          type: 'email',
          values: {
            'smtp_host': 'smtp.example.com',
            'smtp_port': 587,
            'username': 'u',
            'password': 'p',
            'from': 'a@example.com',
            'to': ['b@example.com'],
          },
        );

    test('a valid channel passes', () {
      expect(validateChannel(email(), []), isNull);
    });

    test('a name is required, because a rule refers to it by name', () {
      expect(validateChannel(email(name: '  '), []), contains('name'));
    });

    test('no spaces in a name', () {
      // A rule writes the channel as a bare word; a name with a space can
      // never be referenced.
      expect(validateChannel(email(name: 'house alerts'), []),
          contains('No spaces'));
    });

    test('two channels cannot share a name', () {
      final existing = email(name: 'alerts');
      final fresh = email(name: 'alerts');
      expect(validateChannel(fresh, [existing]), contains('already called'));
    });

    test('a channel is not its own duplicate', () {
      final c = email(name: 'alerts');
      expect(validateChannel(c, [c]), isNull);
    });

    test('a required provider field is required', () {
      final c = email()..values.remove('smtp_host');
      expect(validateChannel(c, []), contains('SMTP host'));

      final empty = email()..values['to'] = <String>[];
      expect(validateChannel(empty, []), contains('To addresses'));
    });

    test('optional fields stay optional', () {
      final c = NotifyChannel(
        name: 'phone',
        type: 'pushover',
        values: {'api_token': 't', 'user_key': 'k'},
      );
      // device and priority are both optional.
      expect(validateChannel(c, []), isNull);
    });
  });

  test('a stored secret is recognised so the editor can leave it alone', () {
    // The editor masks a stored secret and only sends what was retyped.
    // Writing the mask back would replace a working password with dots.
    expect(isStoredSecret('hunter2'), isTrue);
    expect(isStoredSecret(''), isFalse);
    expect(isStoredSecret(null), isFalse);
  });
}
