import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/assets_api.dart';
import 'package:hc_web/core/dashboard/plan_textures.dart';
import 'package:hc_web/core/dashboard/sweet_home.dart';
import 'package:xml/xml.dart';

/// Storing an imported home's floor textures.
///
/// **The only step of an import that can half-fail**, which is the whole reason
/// it is a function taking an uploader rather than a few lines inside a widget:
/// a rule about failure that can only be exercised against a running house is a
/// rule nobody ever checks.
///
/// What every test here asks is the same question — *did the house still
/// arrive?* A picture of a carpet must never cost someone their parsed home.

List<int> _png([int seed = 1]) =>
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, seed];

/// A home of one room per texture named, each floored in the entry given.
SweetHome _home(Map<String, List<int>> textures) {
  final rooms = [
    for (final name in textures.keys)
      "<room name='Room $name'><point x='0' y='0'/><point x='400' y='0'/>"
          "<point x='400' y='400'/>"
          "<texture attribute='floorTexture' name='T' image='$name' "
          "width='100' height='100'/></room>",
  ].join();
  return SweetHome(
    plan: parseHomeXml(
        XmlDocument.parse("<?xml version='1.0'?><home name='T'>$rooms</home>")),
    textures: {
      for (final e in textures.entries) e.key: Uint8List.fromList(e.value),
    },
  );
}

/// An uploader that answers, and remembers what it was asked.
({
  TextureUploader upload,
  List<({String filename, String type, String group})> seen
}) _recorder({Set<String> failOn = const {}}) {
  final seen = <({String filename, String type, String group})>[];
  Future<String> upload(
    Uint8List bytes, {
    required String filename,
    required String contentType,
    required String group,
  }) async {
    seen.add((filename: filename, type: contentType, group: group));
    if (failOn.any(filename.contains)) throw Exception('nope');
    return '/api/v1/assets/${filename.hashCode.abs()}';
  }

  return (upload: upload, seen: seen);
}

void main() {
  test('a home with no textures never reaches the network', () async {
    final recorder = _recorder();
    final result = await storeTextures(_home(const {}), recorder.upload);
    expect(recorder.seen, isEmpty);
    expect(result.refused, 0);
    expect(result.note, isNull);
  });

  test('every floor comes back pointing at what it was stored as', () async {
    final result = await storeTextures(
        _home({'1': _png(1), '2': _png(2)}), _recorder().upload);
    expect(
      [for (final r in result.plan.rooms) r.floor?.url],
      everyElement(isNotNull),
    );
    expect(result.note, isNull);
  });

  test('all of them go to one group, named for the archive', () async {
    final recorder = _recorder();
    await storeTextures(_home({'1': _png(1), '2': _png(2)}), recorder.upload);
    expect(recorder.seen.map((s) => s.group).toSet(), hasLength(1));
    expect(recorder.seen.first.group, startsWith('plan-'));
  });

  test('each is declared as what its bytes say it is', () async {
    final recorder = _recorder();
    await storeTextures(_home({'1': _png()}), recorder.upload);
    expect(recorder.seen.single.type, 'image/png');
    // Named, so the manager shows a plan's textures rather than a row of
    // mysteries nobody dares prune.
    expect(recorder.seen.single.filename, endsWith('.png'));
    expect(recorder.seen.single.filename, startsWith('plan-'));
  });

  test('one that will not store costs its room a floor and nothing more',
      () async {
    final home = _home({'1': _png(1), '2': _png(2)});
    // The uploader's addresses embed the filename, which embeds the entry.
    final result = await storeTextures(home, _recorder(failOn: {'-2.'}).upload);
    expect(result.refused, 1);
    expect(result.plan.rooms, hasLength(2));
    expect(result.plan.rooms.first.floor, isNotNull);
    expect(result.plan.rooms.last.floor, isNull);
    // Said plainly, and not as a failure: the home is on the card.
    expect(result.note, contains('drawn plain'));
    expect(result.note, isNot(contains('failed')));
  });

  test('a texture core would refuse is skipped, never stored under a lie',
      () async {
    final recorder = _recorder();
    // Not an image the store accepts, and with no filename extension to go on
    // there is nothing to declare it as.
    final result = await storeTextures(
        _home({
          '1': const [1, 2, 3, 4, 5, 6, 7, 8]
        }),
        recorder.upload);
    expect(recorder.seen, isEmpty);
    expect(result.refused, 1);
    expect(result.plan.rooms.single.floor, isNull);
  });

  test('one over the size cap does not attempt the round trip', () async {
    final recorder = _recorder();
    final big = Uint8List(maxAssetBytes + 1)..setRange(0, 8, _png());
    final result = await storeTextures(
      SweetHome(plan: _home({'1': _png()}).plan, textures: {'1': big}),
      recorder.upload,
    );
    expect(recorder.seen, isEmpty);
    expect(result.refused, 1);
  });

  test('none of them storing still imports the home', () async {
    final home = _home({'1': _png(1), '2': _png(2)});
    final result =
        await storeTextures(home, _recorder(failOn: {'plan-'}).upload);
    expect(result.refused, 2);
    // The house is the point. It arrived.
    expect(result.plan.rooms, hasLength(2));
    expect(result.note, contains('none of its textures'));
    expect(result.note, contains('The home imported'));
  });

  test('progress is reported per texture, so six uploads look like six',
      () async {
    final steps = <String>[];
    await storeTextures(
      _home({'1': _png(1), '2': _png(2), '3': _png(3)}),
      _recorder().upload,
      onProgress: (done, total) => steps.add('$done/$total'),
    );
    expect(steps, ['1/3', '2/3', '3/3']);
  });
}
