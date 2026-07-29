import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/system_config_api.dart';
import 'package:hc_web/features/plugins/config_descriptor/config_merge.dart';
import 'package:hc_web/features/plugins/config_descriptor/descriptor.dart';

void main() {
  group('reading what core serves', () {
    test('parses the three parts of GET /system/config', () {
      final c = SystemConfig.fromJson(const {
        'raw': '[server]\nport = 8080\n',
        'parsed': {
          'server': {'host': '0.0.0.0', 'port': 8080}
        },
        'path': '/var/lib/homecore/homecore.toml',
      });
      expect(c.raw, contains('[server]'));
      expect((c.parsed['server'] as Map)['port'], 8080);
      expect(c.path, endsWith('homecore.toml'));
    });

    test('a save that says nothing about restarting is assumed to need one',
        () {
      // Core always sends the flag today, but the safe reading of its absence
      // is "yes" — the alternative silently tells the operator their change is
      // live when it is sitting in a file.
      final r = ConfigSaveResult.fromJson(const {'raw': ''});
      expect(r.restartRequired, isTrue);
    });

    test('restart_required: false is honoured', () {
      final r = ConfigSaveResult.fromJson(
          const {'raw': '', 'restart_required': false});
      expect(r.restartRequired, isFalse);
    });
  });

  group('the descriptor core serves is the one the renderer takes', () {
    // A trimmed copy of what GET /system/config/descriptor actually returned
    // from the sandbox — same envelope a plugin publishes.
    const served = {
      'plugin_id': 'homecore',
      'descriptor_version': 1,
      'title': 'Configuration',
      'sections': [
        {
          'id': 'server',
          'title': 'Server',
          'help': 'Where the API and this UI answer.',
          'fields': [
            {
              'key': 'server.host',
              'kind': 'host',
              'label': 'Host',
              'help': 'Bind address. 0.0.0.0 = all interfaces.',
              'default': '0.0.0.0',
            },
            {
              'key': 'server.port',
              'kind': 'port',
              'label': 'Port',
              'default': 8080,
            },
          ],
        },
        {
          'id': 'auth.admin_uds',
          'title': 'Admin socket',
          'fields': [
            {'key': 'auth.admin_uds.enabled', 'kind': 'toggle'},
            {
              'key': 'auth.admin_uds.path',
              'kind': 'text',
              'render': 'path',
              'visible_when': {
                'field': 'auth.admin_uds.enabled',
                'truthy': true
              },
            },
          ],
        },
      ],
    };

    test('deserialises without loss', () {
      final d = ConfigDescriptor.fromJson(Map<String, dynamic>.from(served));
      expect(d.pluginId, 'homecore');
      expect(d.version, 1);
      expect(d.sections.length, 2);

      final server = d.sections.first;
      expect(server.title, 'Server');
      expect(server.fields.map((f) => f.key), ['server.host', 'server.port']);
      expect(server.fields.first.kind, 'host');
      expect(server.fields[1].defaultValue, 8080);
    });

    test('a conditional field keeps its condition', () {
      final d = ConfigDescriptor.fromJson(Map<String, dynamic>.from(served));
      final path = d.sections[1].fields[1];
      // Without this the socket path renders always, including for the houses
      // that have the socket switched off — which is most of them.
      expect(path.visibleWhen, isNotNull);
    });

    test('dotted keys address the nested document core parsed the TOML into',
        () {
      // The renderer walks `server.port` into {"server": {"port": …}}, which is
      // exactly the shape `parsed` arrives in. If either side flattened, every
      // field would read empty and every save would write a junk top-level key.
      final d = ConfigDescriptor.fromJson(Map<String, dynamic>.from(served));
      for (final f in d.sections.expand((s) => s.fields)) {
        expect(f.key, contains('.'), reason: 'every config key is sectioned');
      }
    });
  });

  group('saving sends only what changed', () {
    test('one edited field becomes one section in the patch', () {
      final before = {
        'server': {'host': '0.0.0.0', 'port': 8080},
        'logging': {'level': 'info'},
      };
      final after = {
        'server': {'host': '0.0.0.0', 'port': 8090},
        'logging': {'level': 'info'},
      };

      final patch = diffConfig(before, after);

      // Exactly the shape core's `apply_section_patch` merges through
      // toml_edit: untouched sections are absent, so their comments, ordering
      // and values survive the write.
      expect(patch, {
        'server': {'port': 8090}
      });
      expect(patch.containsKey('logging'), isFalse);
    });

    test('a nested section patches at its own depth', () {
      final before = {
        'auth': {
          'token_expiry_hours': 24,
          'admin_uds': {'enabled': false, 'path': '/run/homecore/admin.sock'},
        },
      };
      final after = {
        'auth': {
          'token_expiry_hours': 24,
          'admin_uds': {'enabled': true, 'path': '/run/homecore/admin.sock'},
        },
      };

      expect(diffConfig(before, after), {
        'auth': {
          'admin_uds': {'enabled': true}
        }
      });
    });

    test('no edit, no request', () {
      final same = {
        'server': {'port': 8080}
      };
      expect(diffConfig(same, Map<String, dynamic>.from(same)), isEmpty);
    });

    test('clearing a field is an explicit null, not a silent drop', () {
      // `null` is how the writer is told to remove the key. Omitting it would
      // read as "unchanged" and the old value would stay in the file.
      final before = {
        'broker': {'tls_port': 8883, 'port': 1883}
      };
      final after = {
        'broker': {'port': 1883}
      };
      expect(diffConfig(before, after), {
        'broker': {'tls_port': null}
      });
    });
  });
}
