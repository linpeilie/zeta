import 'dart:convert';

/// Encodes a canonical project path as a URL-safe, reversible project id.
String encodeWorkspaceProjectId(String canonicalPath) {
  return base64UrlEncode(utf8.encode(canonicalPath)).replaceAll('=', '');
}

/// Decodes a URL-safe project id. Returns `null` when the id is malformed.
String? decodeWorkspaceProjectId(String projectId) {
  final trimmed = projectId.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.contains('/') ||
      trimmed.contains(r'\') ||
      trimmed.contains('+')) {
    return null;
  }
  try {
    final pad = (4 - trimmed.length % 4) % 4;
    final padded = trimmed.padRight(trimmed.length + pad, '=');
    final path = utf8.decode(base64Url.decode(padded));
    if (path.trim().isEmpty) {
      return null;
    }
    return path;
  } on FormatException {
    return null;
  }
}
