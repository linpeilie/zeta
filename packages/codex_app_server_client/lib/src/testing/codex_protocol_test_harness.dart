part of '../datasources/app_server/codex_app_server_agent_provider.dart';

/// Internal access to protocol mappers for focused compatibility tests.
///
/// This class is intentionally omitted from the package barrel. It keeps the
/// public provider surface small while allowing tests to validate tolerant
/// protocol branches without routing every fixture through a live peer.
@visibleForTesting
final class CodexProtocolTestHarness {
  /// Maps one notification and exposes only neutral contract values.
  static ({
    AgentSession? session,
    AgentTurn? startedTurn,
    String? completedSessionId,
    String? completedTurnId,
    List<AgentEvent> events,
    String? ignoredReason,
    String? unmatchedMethod,
  })
  mapNotification(
    JsonRpcNotification notification, {
    String? Function(String threadId)? runningTurnIdForSession,
  }) {
    final mapper = _CodexNotificationMapper(
      providerId: 'codex',
      textCatalog: const _AgentUiTextCatalog(),
    );
    try {
      final mapping = mapper.map(
        notification,
        runningTurnIdForSession: runningTurnIdForSession ?? (String _) => null,
      );
      return (
        session: mapping.session,
        startedTurn: mapping.startedTurn,
        completedSessionId: mapping.completedTurn?.sessionId,
        completedTurnId: mapping.completedTurn?.turnId,
        events: mapping.events,
        ignoredReason: mapping.ignoredReason,
        unmatchedMethod: mapping.unmatchedMethod,
      );
    } finally {
      mapper.dispose();
    }
  }

  /// Maps a sequence with one tracker to validate stateful file projections.
  static List<List<AgentEvent>> mapNotificationSequence(
    Iterable<JsonRpcNotification> notifications,
  ) {
    final mapper = _CodexNotificationMapper(
      providerId: 'codex',
      textCatalog: const _AgentUiTextCatalog(),
    );
    try {
      return notifications
          .map(
            (notification) => mapper
                .map(
                  notification,
                  runningTurnIdForSession: (_) => 'active-turn',
                )
                .events,
          )
          .toList();
    } finally {
      mapper.dispose();
    }
  }

  /// Maps a server request to its neutral permission request.
  static AgentPermissionRequest mapApproval(JsonRpcRequest request) =>
      _CodexApprovalMapper().mapRequest(request).event.request;

  /// Returns the immediate rejection for an unsupported server request.
  static JsonRpcError? approvalRejection(JsonRpcRequest request) =>
      _CodexApprovalMapper().rejectionFor(request);

  /// Encodes a permission decision for the request's concrete protocol method.
  static Object? approvalResponse(
    JsonRpcRequest request,
    AgentPermissionDecision decision,
  ) {
    final mapper = _CodexApprovalMapper();
    final mapped = mapper.mapRequest(request);
    return mapper.approvalResponse(mapped.pendingApproval, decision);
  }

  /// Maps a `skills/list` response and returns its diagnostics.
  static ({
    AgentSkillsCatalog catalog,
    int invalidEntryCount,
    int droppedSkillCount,
  })
  mapSkills(Object? value, {bool includeDisabled = false}) {
    final mapping = _CodexSkillsMapper().catalogFromResult(
      value,
      includeDisabled: includeDisabled,
    );
    return (
      catalog: mapping.catalog,
      invalidEntryCount: mapping.invalidEntryCount,
      droppedSkillCount: mapping.droppedSkillCount,
    );
  }

  /// Parses in-memory Codex session JSONL lines.
  static AgentThreadHistorySnapshot parseJsonl(
    Iterable<String> lines, {
    String fallbackThreadId = 'thread',
  }) {
    final parser = _JsonlHistoryParser(
      fallbackThreadId: fallbackThreadId,
      sessionPath: 'memory.jsonl',
      textCatalog: const _AgentUiTextCatalog(),
    );
    lines.forEach(parser.consumeLine);
    return parser.build();
  }

  /// Maps a `thread/read` result without performing transport I/O.
  static AgentThreadHistorySnapshot mapThreadRead(
    Object? value, {
    String fallbackThreadId = 'thread',
  }) => _CodexThreadHistoryReader(
    textCatalog: const _AgentUiTextCatalog(),
    log: loggerFor('codex.protocol.test'),
  ).threadHistoryFromReadResult(value, fallbackThreadId);

  /// Reads one local session JSONL path through the production reader.
  static Future<AgentThreadHistorySnapshot?> readSessionFile(
    String threadId,
    String? path, {
    bool failRead = false,
  }) => _CodexThreadHistoryReader(
    textCatalog: const _AgentUiTextCatalog(),
    log: loggerFor('codex.protocol.test'),
    openRead: failRead
        ? (_) => throw const FileSystemException('forced read failure')
        : null,
  ).threadHistoryFromSessionFile(threadId, path);

  /// Overlays remote terminal metadata onto a local history snapshot.
  static AgentThreadHistorySnapshot mergeHistory({
    required AgentThreadHistorySnapshot local,
    required AgentThreadHistorySnapshot remote,
  }) => _CodexThreadHistoryReader(
    textCatalog: const _AgentUiTextCatalog(),
    log: loggerFor('codex.protocol.test'),
  ).mergeRemoteTurnFailures(local: local, remote: remote);

  /// Maps a ThreadItem into a tool call.
  static AgentToolCall? mapToolItem(Map<String, Object?> item) =>
      _toolCallFromThreadItem(
        item,
        id: _string(item['id']) ?? 'item',
        status: AgentToolStatus.completed,
        catalog: const _AgentUiTextCatalog(),
      );

  /// Maps a system ThreadItem into a history event.
  static AgentHistoryEventEntry? mapSystemItem(Map<String, Object?> item) =>
      _systemHistoryEventFromThreadItem(
        item,
        id: _string(item['id']) ?? 'item',
        catalog: const _AgentUiTextCatalog(),
      );

  /// Extracts user-visible text from Codex input items.
  static String? userInputText(Object? value) => _userInputText(value);

  /// Extracts local image paths from Codex input items.
  static List<String> userInputLocalImagePaths(Object? value) =>
      _userInputLocalImagePaths(value);

  /// Maps command action descriptions used by approval cards.
  static List<String> commandActionSummaries(Object? value) =>
      _commandActionSummaries(value);

  /// Formats a usage window label.
  static String? usageWindowLabel(int? minutes) =>
      _formatAgentUsageWindowLabelFromMinutes(minutes);

  /// Returns internal fallback labels that remain part of protocol behavior.
  static ({String cancelled, String startFailure, String warning})
  fallbackLabels(
    String providerName,
  ) {
    const catalog = _AgentUiTextCatalog();
    return (
      cancelled: catalog.userCancelled,
      startFailure: catalog.couldNotStart(providerName),
      warning: catalog.protocolWarning(providerName),
    );
  }

  /// Maps initialize metadata into neutral runtime information.
  static AgentRuntimeInfo runtimeInfo(
    Object? value, {
    String? configuredVersion,
  }) => _codexRuntimeInfoFromInitialize(
    value,
    runtimeScope: const AgentRuntimeScope(
      runtimeId: 'test',
      connectionEpoch: 1,
    ),
    configuredVersion: configuredVersion,
    experimentalApiEnabled: true,
  );

  /// Exercises semantic-version comparison and equality contracts.
  static ({bool lessOrEqual, int versionHash}) semanticVersionContract() {
    const current = _CodexSemanticVersion(0, 144, 5);
    const next = _CodexSemanticVersion(0, 145, 0);
    return (lessOrEqual: current <= next, versionHash: current.hashCode);
  }

  /// Classifies collaboration-mode discovery failures for retry behavior.
  static String classifyConversationModeFailure(Object error) =>
      _classifyConversationModeCatalogFailure(error).name;

  /// Runs representative samples for tolerant pure protocol helpers.
  static List<Object?> helperCompatibilitySamples() {
    const catalog = _AgentUiTextCatalog();
    final firstQa = AgentUserInputQaPair(
      questionId: 'q',
      question: 'Question',
      options: const <String>['a'],
      answers: const <String>['a'],
    );
    final changedQa = AgentUserInputQaPair(
      questionId: 'q',
      question: 'Question',
      options: const <String>['b'],
      answers: const <String>['b'],
    );
    return <Object?>[
      _toolTitle(const <String, Object?>{}, catalog),
      _reasoningItemContent(const <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'text': 'reason'},
        ],
      }),
      _reasoningItemContent(const <String, Object?>{'text': 'fallback'}),
      _toolContentFromThreadItem(const <String, Object?>{
        'type': 'mcpToolCall',
        'arguments': <String, Object?>{'x': 1},
      }),
      _toolContentFromThreadItem(const <String, Object?>{
        'type': 'dynamicToolCall',
        'arguments': <String, Object?>{'x': 1},
      }),
      _toolContentFromThreadItem(const <String, Object?>{
        'type': 'imageGeneration',
        'revisedPrompt': 'revised',
      }),
      _webSearchActionPreview(const <String, Object?>{'type': 'future'}),
      _toolCallFromThreadItem(
        const <String, Object?>{
          'id': 'raw-output',
          'type': 'future',
          'result': <String, Object?>{'ok': true},
        },
        id: 'raw-output',
        status: AgentToolStatus.completed,
        catalog: catalog,
      ),
      _pathsFromImageMarkup('[Local image: /tmp/bracket.png]').toList(),
      _joinedStrings(<Object?>['a', null, 'b']),
      _joinedContentItems(<Object?>[
        'a',
        <String, Object?>{'text': 'b'},
      ]),
      _joinedContentItems(const <String, Object?>{'text': 'map text'}),
      _objectPreview(const <Object?>[]),
      _objectPreview('text'),
      _objectPreview(7),
      _jsonlUserMessageText(const <String, Object?>{
        'message': 'hello',
        'text_elements': <Object?>[
          <String, Object?>{'content': 'world'},
        ],
      }),
      _jsonlToolTitle(
        name: 'shell_command',
        catalog: catalog,
        arguments: const <String, Object?>{'command': 'pwd'},
      ),
      _jsonlToolTitle(name: null, catalog: catalog),
      _jsonlToolLocations(
        name: 'read_mcp_resource',
        arguments: const <String, Object?>{
          'uris': <Object?>['file:///a', 'file:///b'],
        },
      ),
      _jsonlToolOutputPreview('header\nOutput:\nactual'),
      _patchPathsFromText('*** Move to: lib/moved.dart'),
      _patchApplyLocations(const <String, Object?>{'lib/a.dart': 'update'}),
      _patchApplyLocations(<Object?>[
        const <String, Object?>{'path': 'lib/b.dart'},
      ]),
      _patchApplySummary(const <String>[], stderr: 'failure'),
      _mcpResultMap(const <String, Object?>{
        'Ok': <String, Object?>{'text': 'ok'},
      }),
      _mcpResultMap(const <String, Object?>{
        'Err': <String, Object?>{'error': 'bad'},
      }),
      _mcpResultIsError(const <String, Object?>{'isError': true}),
      _mcpResultPreview(const <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'content': 'mcp content'},
        ],
      }),
      _mcpResultPreview(const <String, Object?>{'message': 'mcp message'}),
      _webSearchQueryPreview(const <String, Object?>{'query': 'query'}),
      _permissionEventDescription(
        name: 'request_user_input',
        arguments: const <String, Object?>{
          'questions': <Object?>[
            <String, Object?>{'header': 'Header'},
          ],
        },
      ),
      _permissionEventDescription(
        name: 'request_permissions',
        arguments: const <String, Object?>{'reason': 'needed'},
      ),
      _permissionEventDescription(
        name: 'request_permissions',
        arguments: const <String, Object?>{},
        stringInput: 'fallback reason',
      ),
      _permissionEventContent(
        name: 'request_permissions',
        arguments: const <String, Object?>{'scope': 'workspace'},
      ),
      _permissionEventContent(
        name: 'request_permissions',
        stringInput: 'fallback input',
        arguments: const <String, Object?>{},
      ),
      _userInputAnswerLabels(const <String, Object?>{'answer': 'yes'}),
      _userInputAnswerLabels('plain answer'),
      _sameUserInputQaPairs(
        <AgentUserInputQaPair>[firstQa],
        <AgentUserInputQaPair>[changedQa],
      ),
      _sameUserInputQaPairs(
        <AgentUserInputQaPair>[
          AgentUserInputQaPair(
            questionId: 'q',
            question: 'Question',
            answers: const <String>['same', 'A'],
          ),
        ],
        <AgentUserInputQaPair>[
          AgentUserInputQaPair(
            questionId: 'q',
            question: 'Question',
            answers: const <String>['same', 'B'],
          ),
        ],
      ),
      _sameUserInputQaPairs(
        <AgentUserInputQaPair>[
          AgentUserInputQaPair(
            questionId: 'q',
            question: 'Question',
            optionItems: const <AgentUserInputOption>[
              AgentUserInputOption(id: 'same', label: 'A'),
            ],
          ),
        ],
        <AgentUserInputQaPair>[
          AgentUserInputQaPair(
            questionId: 'q',
            question: 'Question',
            optionItems: const <AgentUserInputOption>[
              AgentUserInputOption(id: 'same', label: 'B'),
            ],
          ),
        ],
      ),
      _sameUserInputQaPairs(
        <AgentUserInputQaPair>[
          AgentUserInputQaPair(
            questionId: 'q',
            question: 'Question',
            answers: const <String>['A'],
          ),
        ],
        <AgentUserInputQaPair>[
          AgentUserInputQaPair(
            questionId: 'q',
            question: 'Question',
            answers: const <String>['B'],
          ),
        ],
      ),
      _specialEventContent(const <String, Object?>{'query': 'special query'}),
      _specialEventContent(const <String, Object?>{
        'action': <String, Object?>{'query': 'action query'},
      }),
      _specialEventContent(const <String, Object?>{
        'action': <String, Object?>{'type': 'future'},
      }),
      _historyTurnStatus('inProgress'),
      _unixSecondsToDateTime(1.5),
    ];
  }

  /// Runs path and lifecycle samples for the file-change tracker.
  static List<Object?> fileTrackerCompatibilitySamples() {
    final tracker = CodexFileChangeTracker();
    const scope = AgentRuntimeScope(runtimeId: 'test', connectionEpoch: 1);
    final rename = tracker.projectTurnDiff(
      runtimeScope: scope,
      sessionId: 'thread',
      turnId: 'rename',
      diff:
          'diff --git a/old.dart b/new.dart\n'
          'similarity index 100%\n'
          'rename from old.dart\n'
          'rename to new.dart',
    );
    final quoted = tracker.projectTurnDiff(
      runtimeScope: scope,
      sessionId: 'thread',
      turnId: 'quoted',
      diff:
          'diff --git "a/lib/a b.dart" "b/lib/a b.dart"\n'
          '--- "a/lib/a b.dart"\told\n'
          '+++ "b/lib/a b.dart"\tnew\n'
          '@@ -1 +1 @@\n-old\n+new',
    );
    final malformed = tracker.projectTurnDiff(
      runtimeScope: scope,
      sessionId: 'thread',
      turnId: 'malformed',
      diff: 'diff --git "a/\\q" "b/\\q"\n--- "a/\\q"\n+++ "b/\\q"',
    );
    tracker
      ..invalidateSession(runtimeScope: scope, sessionId: 'thread')
      ..dispose();
    return <Object?>[rename, quoted, malformed];
  }
}
