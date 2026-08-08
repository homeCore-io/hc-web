import 'dart:typed_data';

/// A file the user chose.
///
/// Lives apart from both implementations so the two agree on the type: a
/// `PickedFile` defined twice would be two unrelated classes, and the facade
/// could not name either.
class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}
