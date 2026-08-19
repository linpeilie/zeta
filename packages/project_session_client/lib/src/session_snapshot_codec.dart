import 'package:project_session_client/src/project_session_exceptions.dart';
import 'package:project_session_client/src/session_snapshot_response.dart';

/// Strict codec for the current IDE session snapshot schema.
final class SessionSnapshotCodec {
  /// Creates a current-schema codec.
  const SessionSnapshotCodec();

  /// Encodes [snapshot] to its JSON-compatible current-schema object.
  Map<String, Object?> encode(SessionSnapshotResponse snapshot) {
    final expandedPaths = snapshot.expandedDirectoryPaths.toList()..sort();
    return <String, Object?>{
      'version': projectSessionSchemaVersion,
      'projectPaths': snapshot.projectPaths,
      'activeProjectPath': snapshot.activeProjectPath,
      'currentFilePath': snapshot.currentFilePath,
      'expandedDirectoryPaths': expandedPaths,
      'selectedTreeKey': snapshot.selectedTreeKey,
      'activeAgentProviderId': snapshot.activeAgentProviderId,
      'agentThreadIdsByProject': snapshot.agentThreadIdsByProject,
      'projectThreadExpansionByProject':
          snapshot.projectThreadExpansionByProject,
      'cachedThreadsByProject': <String, Object?>{
        for (final entry in snapshot.cachedThreadsByProject.entries)
          entry.key: entry.value.map(_encodeThread).toList(growable: false),
      },
      'selectedThreadIdsByProject': snapshot.selectedThreadIdsByProject,
      'projectLastOpenedAtByPath': <String, String>{
        for (final entry in snapshot.projectLastOpenedAtByPath.entries)
          entry.key: entry.value.toIso8601String(),
      },
      'projectHomeActive': snapshot.projectHomeActive,
      'workbench': <String, Object?>{
        'leftSidebarVisible': snapshot.workbench.leftSidebarVisible,
        'agentUsageExpanded': snapshot.workbench.agentUsageExpanded,
        'leftSidebarWidth': snapshot.workbench.leftSidebarWidth,
        'agentUsageHeightFraction': snapshot.workbench.agentUsageHeightFraction,
        'selectedAgentUsageProviderId':
            snapshot.workbench.selectedAgentUsageProviderId,
      },
    };
  }

  /// Decodes a current-schema JSON object.
  SessionSnapshotResponse decode(Object? raw) {
    if (raw is! Map<String, Object?>) {
      throw const ProjectSessionDecodeException(
        code: ProjectSessionDecodeFailureCode.invalidRoot,
      );
    }
    if (raw['version'] != projectSessionSchemaVersion) {
      throw const ProjectSessionDecodeException(
        code: ProjectSessionDecodeFailureCode.unsupportedVersion,
        field: 'version',
      );
    }

    return SessionSnapshotResponse(
      projectPaths: _stringList(raw, 'projectPaths'),
      activeProjectPath: _nullableString(raw, 'activeProjectPath'),
      currentFilePath: _nullableString(raw, 'currentFilePath'),
      expandedDirectoryPaths: _stringList(
        raw,
        'expandedDirectoryPaths',
      ).toSet(),
      selectedTreeKey: _nullableString(raw, 'selectedTreeKey'),
      activeAgentProviderId: _nullableString(raw, 'activeAgentProviderId'),
      agentThreadIdsByProject: _stringMap(raw, 'agentThreadIdsByProject'),
      projectThreadExpansionByProject: _boolMap(
        raw,
        'projectThreadExpansionByProject',
      ),
      cachedThreadsByProject: _threadMap(raw, 'cachedThreadsByProject'),
      selectedThreadIdsByProject: _stringMap(
        raw,
        'selectedThreadIdsByProject',
      ),
      projectLastOpenedAtByPath: _dateTimeMap(
        raw,
        'projectLastOpenedAtByPath',
      ),
      projectHomeActive: _bool(raw, 'projectHomeActive'),
      workbench: _workbench(raw, 'workbench'),
    );
  }
}

Map<String, Object?> _encodeThread(SessionThreadSummaryResponse thread) {
  return <String, Object?>{
    'id': thread.id,
    'providerId': thread.providerId,
    'projectPath': thread.projectPath,
    'title': thread.title,
    'sessionPath': thread.sessionPath,
    'preview': thread.preview,
    'createdAt': thread.createdAtMilliseconds,
    'updatedAt': thread.updatedAtMilliseconds,
    'recencyAt': thread.recencyAtMilliseconds,
    'status': thread.status,
    'waitingOnApproval': thread.waitingOnApproval,
    'waitingOnUserInput': thread.waitingOnUserInput,
    'raw': thread.raw,
  };
}

List<String> _stringList(Map<String, Object?> map, String field) {
  final raw = map[field];
  if (raw is! List<Object?> || raw.any((item) => item is! String)) {
    throw _invalidField(field);
  }
  return List<String>.unmodifiable(raw.cast<String>());
}

String? _nullableString(Map<String, Object?> map, String field) {
  final raw = map[field];
  if (raw == null) {
    return null;
  }
  if (raw is! String) {
    throw _invalidField(field);
  }
  return raw;
}

bool _bool(Map<String, Object?> map, String field) {
  final raw = map[field];
  if (raw is! bool) {
    throw _invalidField(field);
  }
  return raw;
}

Map<String, String> _stringMap(Map<String, Object?> map, String field) {
  final raw = map[field];
  if (raw is! Map<String, Object?> ||
      raw.values.any((value) => value is! String)) {
    throw _invalidField(field);
  }
  return Map<String, String>.unmodifiable(raw.cast<String, String>());
}

Map<String, bool> _boolMap(Map<String, Object?> map, String field) {
  final raw = map[field];
  if (raw is! Map<String, Object?> ||
      raw.values.any((value) => value is! bool)) {
    throw _invalidField(field);
  }
  return Map<String, bool>.unmodifiable(raw.cast<String, bool>());
}

Map<String, DateTime> _dateTimeMap(Map<String, Object?> map, String field) {
  final raw = map[field];
  if (raw is! Map<String, Object?>) {
    throw _invalidField(field);
  }
  final result = <String, DateTime>{};
  for (final entry in raw.entries) {
    final value = entry.value;
    if (value is! String) {
      throw _invalidField(field);
    }
    final dateTime = DateTime.tryParse(value);
    if (dateTime == null) {
      throw _invalidField(field);
    }
    result[entry.key] = dateTime;
  }
  return Map<String, DateTime>.unmodifiable(result);
}

Map<String, List<SessionThreadSummaryResponse>> _threadMap(
  Map<String, Object?> map,
  String field,
) {
  final raw = map[field];
  if (raw is! Map<String, Object?>) {
    throw _invalidField(field);
  }
  final result = <String, List<SessionThreadSummaryResponse>>{};
  for (final entry in raw.entries) {
    final threads = entry.value;
    if (threads is! List<Object?>) {
      throw _invalidField(field);
    }
    result[entry.key] = List<SessionThreadSummaryResponse>.unmodifiable(
      threads.map((thread) => _decodeThread(thread, field)),
    );
  }
  return Map<String, List<SessionThreadSummaryResponse>>.unmodifiable(result);
}

SessionThreadSummaryResponse _decodeThread(Object? raw, String field) {
  if (raw is! Map<String, Object?>) {
    throw _invalidField(field);
  }
  final providerRaw = raw['raw'];
  if (providerRaw is! Map<String, Object?>) {
    throw _invalidField(field);
  }
  return SessionThreadSummaryResponse(
    id: _requiredString(raw, 'id', field),
    providerId: _requiredString(raw, 'providerId', field),
    projectPath: _requiredString(raw, 'projectPath', field),
    title: _nestedNullableString(raw, 'title', field),
    sessionPath: _nestedNullableString(raw, 'sessionPath', field),
    preview: _requiredString(raw, 'preview', field, allowEmpty: true),
    createdAtMilliseconds: _requiredInt(raw, 'createdAt', field),
    updatedAtMilliseconds: _requiredInt(raw, 'updatedAt', field),
    recencyAtMilliseconds: _nestedNullableInt(raw, 'recencyAt', field),
    status: _requiredString(raw, 'status', field),
    waitingOnApproval: _nestedBool(raw, 'waitingOnApproval', field),
    waitingOnUserInput: _nestedBool(raw, 'waitingOnUserInput', field),
    raw: Map<String, Object?>.unmodifiable(providerRaw),
  );
}

SessionWorkbenchResponse _workbench(
  Map<String, Object?> map,
  String field,
) {
  final raw = map[field];
  if (raw is! Map<String, Object?>) {
    throw _invalidField(field);
  }
  final leftSidebarVisible = raw['leftSidebarVisible'];
  final agentUsageExpanded = raw['agentUsageExpanded'];
  final leftSidebarWidth = raw['leftSidebarWidth'];
  final agentUsageHeightFraction = raw['agentUsageHeightFraction'];
  final providerId = raw['selectedAgentUsageProviderId'];
  if (leftSidebarVisible is! bool ||
      agentUsageExpanded is! bool ||
      !_isNullableNumber(leftSidebarWidth) ||
      !_isNullableNumber(agentUsageHeightFraction) ||
      providerId != null && providerId is! String) {
    throw _invalidField(field);
  }
  final sidebarWidth = (leftSidebarWidth as num?)?.toDouble();
  final usageFraction = (agentUsageHeightFraction as num?)?.toDouble();
  if (sidebarWidth != null && (!sidebarWidth.isFinite || sidebarWidth <= 0) ||
      usageFraction != null &&
          (!usageFraction.isFinite ||
              usageFraction <= 0 ||
              usageFraction >= 1)) {
    throw _invalidField(field);
  }
  return SessionWorkbenchResponse(
    leftSidebarVisible: leftSidebarVisible,
    agentUsageExpanded: agentUsageExpanded,
    leftSidebarWidth: sidebarWidth,
    agentUsageHeightFraction: usageFraction,
    selectedAgentUsageProviderId: providerId as String?,
  );
}

bool _isNullableNumber(Object? value) => value == null || value is num;

String _requiredString(
  Map<String, Object?> map,
  String key,
  String field, {
  bool allowEmpty = false,
}) {
  final value = map[key];
  if (value is! String || !allowEmpty && value.isEmpty) {
    throw _invalidField(field);
  }
  return value;
}

int _requiredInt(Map<String, Object?> map, String key, String field) {
  final value = map[key];
  if (value is! int) {
    throw _invalidField(field);
  }
  return value;
}

String? _nestedNullableString(
  Map<String, Object?> map,
  String key,
  String field,
) {
  final value = map[key];
  if (value != null && value is! String) {
    throw _invalidField(field);
  }
  return value as String?;
}

int? _nestedNullableInt(
  Map<String, Object?> map,
  String key,
  String field,
) {
  final value = map[key];
  if (value != null && value is! int) {
    throw _invalidField(field);
  }
  return value as int?;
}

bool _nestedBool(Map<String, Object?> map, String key, String field) {
  final value = map[key];
  if (value is! bool) {
    throw _invalidField(field);
  }
  return value;
}

ProjectSessionDecodeException _invalidField(String field) {
  return ProjectSessionDecodeException(
    code: ProjectSessionDecodeFailureCode.invalidField,
    field: field,
  );
}
