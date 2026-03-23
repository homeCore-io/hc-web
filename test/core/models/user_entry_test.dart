import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/user_entry.dart';

void main() {
  group('UserEntry.fromJson', () {
    test('parses admin user', () {
      final u = UserEntry.fromJson({
        'id': 'a1b2c3d4-0000-0000-0000-000000000001',
        'username': 'alice',
        'role': 'admin',
        'created_at': '2026-01-01T00:00:00Z',
      });

      expect(u.id, 'a1b2c3d4-0000-0000-0000-000000000001');
      expect(u.username, 'alice');
      expect(u.role, 'admin');
      expect(u.displayRole, 'Admin');
    });

    test('parses user role', () {
      final u = UserEntry.fromJson({
        'id': 'id-2',
        'username': 'bob',
        'role': 'user',
        'created_at': '2026-02-01T00:00:00Z',
      });

      expect(u.displayRole, 'User');
    });

    test('parses read_only role', () {
      final u = UserEntry.fromJson({
        'id': 'id-3',
        'username': 'carol',
        'role': 'read_only',
        'created_at': '2026-03-01T00:00:00Z',
      });

      expect(u.displayRole, 'Read Only');
    });

    test('defaults role to user on missing field', () {
      final u = UserEntry.fromJson({
        'id': 'id-4',
        'username': 'dave',
        'created_at': '2026-03-01T00:00:00Z',
      });

      expect(u.role, 'user');
    });

    test('handles missing created_at', () {
      final u = UserEntry.fromJson({
        'id': 'id-5',
        'username': 'eve',
        'role': 'admin',
      });

      expect(u.createdAt, '');
    });

    test('unknown role falls through to raw string', () {
      final u = UserEntry.fromJson({
        'id': 'id-6',
        'username': 'frank',
        'role': 'superuser',
        'created_at': '',
      });

      expect(u.displayRole, 'superuser');
    });
  });
}
