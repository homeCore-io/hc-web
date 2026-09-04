import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/presentation.dart';

/// **On a room page the room is the one word every device shares.**
///
/// The Living Room's lamps are *Living Room Floor Lamp*, *Living Room Tower
/// Lamp* and *Living Room Arch Lamp*. On a page whose title and crumb both say
/// Living Room, the prefix is the only part that survives a narrow tile and the
/// word that tells them apart is the one ellipsised away — three tiles reading
/// "Living Room …". John: *"strip the room name from device labels."*
void main() {
  _suffixes();
  test('the prefix comes off, however either side is spelled', () {
    expect(labelInRoom('Living Room Floor Lamp', 'living_room'), 'Floor Lamp');
    expect(labelInRoom('Living Room Floor Lamp', 'Living Room'), 'Floor Lamp');
    expect(labelInRoom('Master Bedroom Fan', 'master_bedroom'), 'Fan');
  });

  test('and the separator with it', () {
    expect(labelInRoom('Lock - Living Room', 'lock'), 'Living Room');
    expect(labelInRoom('Office: Desk Lamp', 'office'), 'Desk Lamp');
    expect(labelInRoom('Office_Desk Lamp', 'office'), 'Desk Lamp');
  });

  test('a name that is only the room keeps its name', () {
    // The Hue group IS called "Living Room". A tile labelled with the empty
    // string is worse than a repeated word.
    expect(labelInRoom('Living Room', 'living_room'), 'Living Room');
  });

  test('a name that merely starts with the same letters is left alone', () {
    // "Officer" is not "Office" plus a separator.
    expect(labelInRoom('Offices Are Fun', 'office'), 'Offices Are Fun');
    expect(labelInRoom('Kitchen Sink', 'living_room'), 'Kitchen Sink');
  });

  test('no room means no stripping', () {
    expect(
        labelInRoom('Living Room Floor Lamp', null), 'Living Room Floor Lamp');
    expect(labelInRoom('Living Room Floor Lamp', ''), 'Living Room Floor Lamp');
  });
}

/// **Either end.**
///
/// This house names things both ways round — *Living Room Floor Lamp* and
/// *Lock - Living Room* — and a rule that only knew about prefixes left half
/// the labels saying the room and nothing else once a narrow tile had finished
/// with them.
void _suffixes() {
  group('the room at the end', () {
    test('comes off too, separator and all', () {
      expect(labelInRoom('Lock - Living Room', 'living_room'), 'Lock');
      expect(labelInRoom('Outlet - Living Room AC', 'living_room'),
          'Outlet - Living Room AC',
          reason: 'the room is in the middle, and cutting there is guessing');
      expect(labelInRoom('Overhead Office', 'office'), 'Overhead');
    });

    test('and a name that is only the room still keeps it', () {
      expect(labelInRoom('Living Room', 'living_room'), 'Living Room');
    });

    test('a room that is neither end is left alone', () {
      expect(labelInRoom('Lock Office Door', 'kitchen'), 'Lock Office Door');
    });
  });
}
