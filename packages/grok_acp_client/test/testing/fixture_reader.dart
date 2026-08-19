import 'dart:convert';
import 'dart:io';

String readFixtureText(String relativePath) {
  return File('test/fixtures/$relativePath').readAsStringSync();
}

Map<String, Object?> readFixtureJsonMap(String relativePath) {
  final decoded = jsonDecode(readFixtureText(relativePath));
  if (decoded is! Map) {
    throw StateError('Fixture $relativePath is not a JSON object');
  }
  return decoded.map(
    (key, value) => MapEntry(key.toString(), value as Object?),
  );
}
