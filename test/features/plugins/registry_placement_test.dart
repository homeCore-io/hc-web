import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/registry_plugin.dart';

/// What the catalogue can say before anyone clicks Install.
///
/// The rule that matters: a plugin no enrolled runtime can host is **still
/// shown**. Hiding it leaves an operator wondering why the catalogue is missing
/// something they read about, and the fix — enrol a runtime — is invisible from
/// a row that is not there.

RegistryPlugin _fromIndex({
  required String id,
  required List<Map<String, dynamic>> artifacts,
  String version = '0.1.0',
}) =>
    RegistryPlugin.fromJson({
      'id': id,
      'name': id,
      'versions': [
        {'version': version, 'artifacts': artifacts},
      ],
    });

const _native = {'os': 'linux', 'arch': 'x86_64'};
const _python = {
  'os': 'linux',
  'arch': 'x86_64',
  'runtime': 'python',
  'abi': 'cp312-manylinux_2_28',
};

void main() {
  _updateClaims();

  group('reading a registry entry', () {
    /// Every entry published before plugin runtimes existed omits `runtime`
    /// entirely, and means native. Defaulting it wrong would make the whole
    /// existing catalogue look like it needed a runtime.
    test('an artifact with no runtime key is native', () {
      final p = _fromIndex(id: 'plugin.caseta', artifacts: [_native]);
      expect(p.artifactsFor('0.1.0').single.isNative, isTrue);
      expect(p.needsRuntime('0.1.0'), isFalse);
    });

    test('a python artifact carries its abi and needs a runtime', () {
      final p = _fromIndex(id: 'plugin.virtuallight', artifacts: [_python]);
      final a = p.artifactsFor('0.1.0').single;
      expect(a.isNative, isFalse);
      expect(a.abi, 'cp312-manylinux_2_28');
      expect(p.needsRuntime('0.1.0'), isTrue);
      expect(a.requirement, contains('python'));
    });

    /// A version publishing both is installable here, and core prefers the
    /// native one — so the row must not offer to place it on a runtime.
    test('a version with a native artifact does not need a runtime', () {
      final p = _fromIndex(id: 'plugin.both', artifacts: [_native, _python]);
      expect(p.needsRuntime('0.1.0'), isFalse);
      expect(p.runtimeArtifacts('0.1.0').length, 1);
    });

    /// An entry that lists no artifacts at all says nothing about where it
    /// runs, and must not be reported as needing a runtime — the row falls
    /// back to a plain Install and lets core answer.
    test('no artifacts is not a runtime requirement', () {
      final p = _fromIndex(id: 'plugin.silent', artifacts: []);
      expect(p.needsRuntime('0.1.0'), isFalse);
    });

    /// The catalogue asks about the newest version, and versions differ: a
    /// plugin that was native at 0.1.0 and is python at 0.2.0 must be read at
    /// 0.2.0.
    test('artifacts are per version, and default to the newest', () {
      final p = RegistryPlugin.fromJson({
        'id': 'plugin.moved',
        'versions': [
          {
            'version': '0.1.0',
            'artifacts': [_native],
          },
          {
            'version': '0.2.0',
            'artifacts': [_python],
          },
        ],
      });
      expect(p.latest, '0.2.0');
      expect(p.needsRuntime(null), isTrue, reason: 'null means the newest');
      expect(p.needsRuntime('0.1.0'), isFalse);
    });
  });
}

/// "An update is available" is a claim, and an unknown installed version is not
/// evidence for it.
///
/// A hosted plugin registers itself over MQTT — core never unpacked a binary
/// and reports no installed version — so comparing `latest != installedVersion`
/// directly offered `Update to v0.1.0` on a plugin already running v0.1.0.
void _updateClaims() {
  group('claiming an update', () {
    final p = RegistryPlugin.fromJson({
      'id': 'plugin.x',
      'versions': [
        {'version': '0.1.0', 'artifacts': []},
      ],
    });

    test('an unknown installed version claims nothing', () {
      expect(p.updateFrom(null), isNull);
      expect(p.updateFrom(''), isNull);
    });

    test('the same version claims nothing', () {
      expect(p.updateFrom('0.1.0'), isNull);
    });

    test('an older version does claim one', () {
      expect(p.updateFrom('0.0.9'), '0.1.0');
    });
  });
}
