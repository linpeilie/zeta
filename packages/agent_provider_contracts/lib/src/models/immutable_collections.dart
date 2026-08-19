/// Returns an unmodifiable snapshot of [values].
List<T> immutableList<T>(Iterable<T> values) => List<T>.unmodifiable(values);

/// Returns an unmodifiable snapshot of [values].
Map<K, V> immutableMap<K, V>(Map<K, V> values) =>
    Map<K, V>.unmodifiable(values);

/// Returns an unmodifiable map whose list values are also snapshots.
Map<K, List<V>> immutableListMap<K, V>(Map<K, List<V>> values) =>
    Map<K, List<V>>.unmodifiable(
      values.map(
        (key, value) => MapEntry<K, List<V>>(key, immutableList(value)),
      ),
    );

/// Returns a recursively frozen snapshot of a JSON-like diagnostic payload.
Map<String, Object?> immutableJsonMap(Map<String, Object?> values) =>
    Map<String, Object?>.unmodifiable(
      values.map(
        (key, value) => MapEntry<String, Object?>(key, _immutableValue(value)),
      ),
    );

Object? _immutableValue(Object? value) {
  if (value is Map) {
    return Map<Object?, Object?>.unmodifiable(
      value.map(
        (key, nestedValue) =>
            MapEntry<Object?, Object?>(key, _immutableValue(nestedValue)),
      ),
    );
  }
  if (value is Iterable) {
    return List<Object?>.unmodifiable(value.map(_immutableValue));
  }
  return value;
}
