String? decodeOptionalString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

List<String> decodeStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.whereType<String>().where((item) => item.isNotEmpty).toList();
}

Map<String, String> decodeStringMap(Object? value) {
  if (value is! Map) {
    return const <String, String>{};
  }

  final result = <String, String>{};
  for (final entry in value.entries) {
    final key = entry.key;
    final item = entry.value;
    if (key is String) {
      result[key] = item is String ? item : '$item';
    }
  }
  return result;
}

Map<String, Object?> decodeObjectMap(Object? value) {
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is String) {
        result[entry.key as String] = entry.value;
      }
    }
    return Map<String, Object?>.unmodifiable(result);
  }
  return const <String, Object?>{};
}

DateTime? decodeDateTimeFromMilliseconds(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  return null;
}
