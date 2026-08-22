/// 集合的浅层结构相等。
///
/// 纯 Dart 层不能用 `package:flutter/foundation.dart` 的 `listEquals` /
/// `mapEquals`，这里提供等价实现，语义保持一致：逐元素 `==`，不做深比较。
bool zetaListEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a == null || b == null || a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

/// Map 的浅层结构相等：键集合相同且逐键值 `==`。
bool zetaMapEquals<K, V>(Map<K, V>? a, Map<K, V>? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a == null || b == null || a.length != b.length) {
    return false;
  }
  for (final key in a.keys) {
    if (!b.containsKey(key) || b[key] != a[key]) {
      return false;
    }
  }
  return true;
}
