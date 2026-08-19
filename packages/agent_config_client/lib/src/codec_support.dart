import 'dart:convert';

import 'package:agent_config_client/src/agent_config_decode_exception.dart';

/// Decodes a JSON object and converts parser failures to the stable exception.
Map<String, Object?> decodeJsonObject(
  String source,
  AgentConfigDocumentKind document,
) {
  Object? value;
  try {
    value = jsonDecode(source);
  } on FormatException {
    throw AgentConfigDecodeException(
      document: document,
      reason: AgentConfigDecodeReason.invalidJson,
    );
  }
  return requireObject(value, document);
}

/// Requires a string-keyed object.
Map<String, Object?> requireObject(
  Object? value,
  AgentConfigDocumentKind document,
) {
  if (value is! Map<String, Object?>) {
    throw AgentConfigDecodeException(
      document: document,
      reason: AgentConfigDecodeReason.invalidShape,
    );
  }
  return Map<String, Object?>.from(value);
}

/// Requires a JSON list.
List<Object?> requireList(
  Object? value,
  AgentConfigDocumentKind document,
) {
  if (value is! List) {
    throw AgentConfigDecodeException(
      document: document,
      reason: AgentConfigDecodeReason.invalidShape,
    );
  }
  return value.cast<Object?>();
}

/// Requires a non-empty string.
String requireString(
  Object? value,
  AgentConfigDocumentKind document,
) {
  if (value is! String || value.trim().isEmpty) {
    throw AgentConfigDecodeException(
      document: document,
      reason: AgentConfigDecodeReason.invalidShape,
    );
  }
  return value;
}

/// Requires either `null` or a non-empty string.
String? requireNullableString(
  Object? value,
  AgentConfigDocumentKind document,
) {
  if (value == null) {
    return null;
  }
  return requireString(value, document);
}

/// Requires a Boolean.
bool requireBool(Object? value, AgentConfigDocumentKind document) {
  if (value is! bool) {
    throw AgentConfigDecodeException(
      document: document,
      reason: AgentConfigDecodeReason.invalidShape,
    );
  }
  return value;
}

/// Requires the exact current schema version.
int requireVersion(
  Map<String, Object?> root,
  int currentVersion,
  AgentConfigDocumentKind document,
) {
  final version = root['version'];
  if (version != currentVersion) {
    throw AgentConfigDecodeException(
      document: document,
      reason: AgentConfigDecodeReason.unsupportedVersion,
    );
  }
  return version! as int;
}

/// Requires a parseable date and normalizes it to UTC.
DateTime requireDateTime(
  Object? value,
  AgentConfigDocumentKind document,
) {
  final source = requireString(value, document);
  final result = DateTime.tryParse(source);
  if (result == null) {
    throw AgentConfigDecodeException(
      document: document,
      reason: AgentConfigDecodeReason.invalidShape,
    );
  }
  return result.toUtc();
}

/// Raises a stable duplicate-identifier failure.
Never duplicateIdentifier(AgentConfigDocumentKind document) {
  throw AgentConfigDecodeException(
    document: document,
    reason: AgentConfigDecodeReason.duplicateIdentifier,
  );
}
