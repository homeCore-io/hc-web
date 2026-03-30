String? readSingleDeviceRef(
  Map<String, dynamic> data, {
  String primaryKey = 'device',
  String legacyKey = 'device_id',
}) {
  final raw = data[primaryKey] ?? data[legacyKey];
  if (raw is String && raw.isNotEmpty) return raw;
  return null;
}

List<String> readDeviceRefs(
  Map<String, dynamic> data, {
  String primaryKey = 'device',
  String primaryListKey = 'devices',
  String legacyKey = 'device_id',
  String legacyListKey = 'device_ids',
}) {
  final refs = <String>[];

  void add(dynamic value) {
    if (value is String && value.isNotEmpty && !refs.contains(value)) {
      refs.add(value);
    }
  }

  add(data[primaryKey]);
  add(data[legacyKey]);

  for (final key in [primaryListKey, legacyListKey]) {
    final raw = data[key];
    if (raw is List) {
      for (final item in raw) {
        add(item);
      }
    }
  }

  return refs;
}

void writeSingleDeviceRef(
  Map<String, dynamic> data,
  String? ref, {
  String primaryKey = 'device',
  String legacyKey = 'device_id',
}) {
  data.remove(primaryKey);
  data.remove(legacyKey);
  if (ref != null && ref.isNotEmpty) {
    data[primaryKey] = ref;
  }
}

void writeDeviceRefs(
  Map<String, dynamic> data,
  List<String> refs, {
  String primaryKey = 'device',
  String primaryListKey = 'devices',
  String legacyKey = 'device_id',
  String legacyListKey = 'device_ids',
}) {
  data.remove(primaryKey);
  data.remove(primaryListKey);
  data.remove(legacyKey);
  data.remove(legacyListKey);

  final normalized = refs.where((ref) => ref.isNotEmpty).toList();
  if (normalized.isEmpty) return;

  data[primaryKey] = normalized.first;
  if (normalized.length > 1) {
    data[primaryListKey] = normalized.sublist(1);
  }
}
