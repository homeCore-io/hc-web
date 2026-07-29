import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/registry_plugin.dart';

RegistryPlugin entry(List<String> versions) =>
    RegistryPlugin(id: 'plugin.lutron', name: 'Lutron', versions: versions);

void main() {
  group('is there a newer version', () {
    test('a newer registry version is offered', () {
      expect(entry(['0.1.7', '0.1.8']).updateFrom('0.1.7'), '0.1.8');
    });

    test('being up to date offers nothing', () {
      expect(entry(['0.1.7', '0.1.8']).updateFrom('0.1.8'), isNull);
    });

    test('a locally built version ahead of the registry offers nothing', () {
      // Normal in this workspace: a plugin built from the tree can be newer
      // than anything published. Offering a "downgrade" as an update would be
      // worse than saying nothing.
      expect(entry(['0.1.7']).updateFrom('0.1.9'), isNull);
    });

    test('0.1.10 is newer than 0.1.9, whatever the strings say', () {
      // The trap in taking `versions.last`, or in comparing as text.
      expect(entry(['0.1.9', '0.1.10']).updateFrom('0.1.9'), '0.1.10');
      expect(entry(['0.1.10', '0.1.9']).latest, '0.1.10');
      expect(RegistryPlugin.compareVersions('0.1.10', '0.1.9'), greaterThan(0));
    });

    test('order in the index does not decide it', () {
      // The index is published in order today; that is a convention, not a
      // guarantee, and nothing here should depend on it.
      expect(entry(['0.2.0', '0.1.8']).latest, '0.2.0');
      expect(entry(['0.2.0', '0.1.8']).updateFrom('0.1.8'), '0.2.0');
    });

    test('an unknown installed version makes no claim', () {
      // "An update is available" is a claim about what you are running. With
      // nothing to compare against, silence is the honest answer.
      expect(entry(['0.1.8']).updateFrom(null), isNull);
      expect(entry(['0.1.8']).updateFrom(''), isNull);
    });

    test('an empty registry entry makes no claim', () {
      expect(entry(const []).updateFrom('0.1.8'), isNull);
      expect(entry(const []).latest, isNull);
    });

    test('a suffixed version is ordered rather than crashing', () {
      expect(RegistryPlugin.compareVersions('0.2.0', '0.2.0-rc1'), isNot(0));
      expect(entry(['0.2.0-rc1', '0.2.0']).latest, '0.2.0');
    });

    test('differing segment counts compare sanely', () {
      expect(RegistryPlugin.compareVersions('0.2', '0.2.1'), lessThan(0));
      expect(RegistryPlugin.compareVersions('1.0', '0.9.9'), greaterThan(0));
    });
  });
}
