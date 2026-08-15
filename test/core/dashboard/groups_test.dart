import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/groups.dart';

/// Holding several elements as one thing, and letting go without losing them.
void main() {
  group('the path is the group', () {
    test('reads what is there', () {
      expect(groupOf(const {'group': 'Wall/Lights'}), 'Wall/Lights');
      expect(groupOf(const {}), isNull);
    });

    test('a hand-edited document cannot make an unreachable group', () {
      // Empty segments would produce a path that matches nothing: its members
      // are hidden from every group operation and cannot be selected to be
      // fixed. Normalising on the way out is the same defensiveness `zOf`
      // shows for a `z` of 1e9.
      expect(groupOf(const {'group': '//Wall//Lights//'}), 'Wall/Lights');
      expect(groupOf(const {'group': '  Wall / Lights '}), 'Wall/Lights');
      expect(groupOf(const {'group': '///'}), isNull);
      expect(groupOf(const {'group': ''}), isNull);
      expect(groupOf(const {'group': 7}), isNull);
    });

    test('ungrouping leaves the document as it was found', () {
      // Not `group: null` — an idle click that groups and ungroups must not
      // leave a trace in the saved JSON.
      final before = <String, dynamic>{'markdown': 'x'};
      final after = withGroup(withGroup(before, 'Lights'), null);
      expect(after, before);
      expect(after.containsKey('group'), isFalse);
    });

    test('writing a path normalises it too', () {
      expect(withGroup(const {}, ' Wall // Lights ')['group'], 'Wall/Lights');
    });
  });

  group('reading a path', () {
    test('names the last part and points at the rest', () {
      expect(nameOf('Wall/Lights'), 'Lights');
      expect(parentOf('Wall/Lights'), 'Wall');
      expect(parentOf('Wall'), isNull);
    });

    test('inside is about segments, not letters', () {
      // The bug a plain `startsWith` would have: `Wallpaper` is not in `Wall`.
      expect(isUnder('Wall/Lights', 'Wall'), isTrue);
      expect(isUnder('Wall', 'Wall'), isTrue);
      expect(isUnder('Wallpaper', 'Wall'), isFalse);
    });

    test('relative names what is left below where you stand', () {
      expect(relativeTo('Wall/Lights/Lamp', 'Wall'), 'Lights/Lamp');
      expect(relativeTo('Wall', 'Wall'), isNull, reason: 'nothing is left');
      expect(relativeTo('Other', 'Wall'), isNull);
      expect(relativeTo('Wall/Lights', null), 'Wall/Lights');
    });
  });

  group('who is in it', () {
    final paths = {
      'a': 'Wall',
      'b': 'Wall/Lights',
      'c': 'Wallpaper',
      'd': null,
    };

    test('takes everything below, at any depth', () {
      expect(membersOf(paths, 'Wall'), {'a', 'b'});
    });

    test('and nothing that merely starts the same way', () {
      expect(membersOf(paths, 'Wallpaper'), {'c'});
    });

    test('a group with nobody in it is not a group', () {
      // No registry, so this cannot be a stale entry — it is simply empty.
      expect(membersOf(paths, 'Kitchen'), isEmpty);
    });
  });

  group('what a click holds', () {
    test('the outermost group, not the card', () {
      // The whole point: one click holds the cluster.
      expect(clickTarget('Wall/Lights', null), 'Wall');
    });

    test('an ungrouped card is just itself', () {
      expect(clickTarget(null, null), isNull);
    });

    test('standing inside, it holds the next level down', () {
      expect(clickTarget('Wall/Lights', 'Wall'), 'Wall/Lights');
    });

    test('a direct member of where you stand is the card itself', () {
      // As deep as this element goes — there is nothing left to hold.
      expect(clickTarget('Wall', 'Wall'), isNull);
    });

    test('clicking outside the group you are in takes you out of it', () {
      // Ignoring the click would be a canvas that stops responding for reasons
      // nothing on screen explains.
      expect(clickTarget('Kitchen/Hob', 'Wall'), 'Kitchen');
      expect(clickTarget(null, 'Wall'), isNull);
    });
  });

  group('the group in hand', () {
    test('is what they all share', () {
      expect(commonGroup(['Wall/Lights', 'Wall/Lights']), 'Wall/Lights');
      expect(commonGroup(['Wall/Lights', 'Wall/Sockets']), 'Wall');
    });

    test('is nothing when one of them is loose', () {
      expect(commonGroup(['Wall', null]), isNull);
    });

    test('is nothing when they share no group at all', () {
      expect(commonGroup(['Wall', 'Kitchen']), isNull);
    });

    test('is nothing when nothing is held', () {
      expect(commonGroup([]), isNull);
    });

    test('does not match half a name', () {
      expect(commonGroup(['Wall', 'Wallpaper']), isNull);
    });
  });

  group('naming', () {
    test('numbers from one and fills the gaps', () {
      // Group, ungroup, group again should give `Group 1` back rather than
      // climbing forever.
      expect(freshName({}), 'Group 1');
      expect(freshName({'Group 1'}), 'Group 2');
      expect(freshName({'Group 2'}), 'Group 1');
    });

    test('only counts the level you are on', () {
      final paths = ['Wall', 'Wall/Group 1', 'Kitchen'];
      expect(namesIn(paths, null), {'Wall', 'Kitchen'});
      expect(namesIn(paths, 'Wall'), {'Group 1'});
      expect(freshName(namesIn(paths, 'Wall')), 'Group 2');
      // `Group 1` is free at the top even though it exists inside `Wall`.
      expect(freshName(namesIn(paths, null)), 'Group 1');
    });

    test('siblings cannot share a name, because the name is the address', () {
      // Letting two groups share one would merge them — a far worse surprise
      // than a number appearing after what was typed.
      expect(uniqueName('Lights', {'Lights'}), 'Lights 2');
      expect(uniqueName('Lights', {'Lights', 'Lights 2'}), 'Lights 3');
      expect(uniqueName('Lights', {}), 'Lights');
    });

    test('a name with a separator in it cannot smuggle in a level', () {
      // Otherwise renaming a group to `a/b` moves it, silently.
      expect(uniqueName('Wall/Lights', {}), 'Lights');
      expect(uniqueName('   ', {}), 'Group');
    });
  });

  group('grouping', () {
    test('a loose card joins the new group', () {
      expect(regrouped(null, 'Group 1', null), 'Group 1');
    });

    test('a group put in a group keeps its own shape', () {
      // Grouping a cluster with a loose card must not dissolve the cluster.
      expect(regrouped('Group 1', 'Group 2', null), 'Group 2/Group 1');
      expect(regrouped(null, 'Group 2', null), 'Group 2');
    });

    test('nests below where you are standing', () {
      expect(regrouped('Wall/Lights', 'Wall/Group 1', 'Wall'),
          'Wall/Group 1/Lights');
    });

    test('deeply nested members keep every level', () {
      expect(regrouped('A/B/C', 'New', null), 'New/A/B/C');
    });
  });

  group('ungrouping', () {
    test('dissolves the one named, not the innermost', () {
      // Holding `Wall` and ungrouping must leave `Lights` standing, or it takes
      // apart something other than what is in hand.
      expect(ungrouped('Wall/Lights', 'Wall'), 'Lights');
      expect(ungrouped('Wall', 'Wall'), isNull);
    });

    test('keeps what is above it', () {
      expect(ungrouped('A/B/C', 'A/B'), 'A/C');
    });

    test('leaves anything not in it alone', () {
      expect(ungrouped('Kitchen', 'Wall'), 'Kitchen');
      expect(ungrouped(null, 'Wall'), isNull);
      expect(ungrouped('Wallpaper', 'Wall'), 'Wallpaper');
    });
  });

  group('renaming', () {
    test('carries everything under it', () {
      expect(renamedPath('Wall/Lights', 'Wall', 'Outside'), 'Outside/Lights');
      expect(renamedPath('Wall', 'Wall', 'Outside'), 'Outside');
    });

    test('leaves the rest of the page alone', () {
      expect(renamedPath('Kitchen', 'Wall', 'Outside'), 'Kitchen');
      expect(renamedPath('Wallpaper', 'Wall', 'Outside'), 'Wallpaper');
      expect(renamedPath(null, 'Wall', 'Outside'), isNull);
    });

    test('renames a nested group in place', () {
      expect(renamedPath('A/B/C', 'A/B', 'A/Renamed'), 'A/Renamed/C');
    });
  });

  test('stepping out goes up one level, then out altogether', () {
    expect(stepOut('Wall/Lights'), 'Wall');
    expect(stepOut('Wall'), isNull);
    expect(stepOut(null), isNull);
  });
}
