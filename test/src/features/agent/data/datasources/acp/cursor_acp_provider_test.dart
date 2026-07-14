import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_acp_agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_session_index_store.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('CursorAcpAgentProvider', () {
    test('requires a workspace before initialize', () async {
      // Arrange
      final provider = CursorAcpAgentProvider(
        config: AgentProviderConfig.defaultCursor,
        peer: _FakeCursorPeer(),
        sessionIndexStore: MemoryCursorSessionIndexStore(),
      );
      addTearDown(provider.dispose);

      // Act / Assert
      await expectLater(provider.initialize(), throwsStateError);
      expect(provider.capabilities.bootstrapPolicy.requiresWorkspace, isTrue);
    });

    test('initializes, authenticates, starts and prompts', () async {
      // Arrange
      final peer = _FakeCursorPeer();
      final provider = CursorAcpAgentProvider(
        config: AgentProviderConfig.defaultCursor,
        peer: peer,
        sessionIndexStore: MemoryCursorSessionIndexStore(),
      );
      addTearDown(provider.dispose);

      // Act
      final session = await provider.startSession(
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
      );
      final turn = await provider.sendMessage(
        session: session,
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
        message: 'hello cursor',
      );

      // Assert
      expect(session.id, 'cursor-session-1');
      expect(turn.sessionId, session.id);
      expect(
        peer.requestMethods,
        containsAll(<String>[
          'initialize',
          'authenticate',
          'session/new',
          'session/prompt',
        ]),
      );
      final initialize = peer.paramsFor('initialize');
      expect(initialize['protocolVersion'], 1);
      expect(provider.capabilities.supportsLocalImageInput, isFalse);
      expect(provider.capabilities.supportsResourceInput, isFalse);
    });

    test('maps streaming messages, tools and plans', () async {
      // Arrange
      final peer = _FakeCursorPeer();
      final provider = CursorAcpAgentProvider(
        config: AgentProviderConfig.defaultCursor,
        peer: peer,
        sessionIndexStore: MemoryCursorSessionIndexStore(),
      );
      addTearDown(provider.dispose);
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);
      addTearDown(subscription.cancel);
      await provider.startSession(
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
      );

      // Act
      peer.emitUpdate(<String, Object?>{
        'sessionUpdate': 'agent_message_chunk',
        'messageId': 'message-1',
        'content': <String, Object?>{'type': 'text', 'text': 'Hello'},
      });
      peer.emitUpdate(<String, Object?>{
        'sessionUpdate': 'tool_call',
        'toolCallId': 'tool-1',
        'title': 'Read file',
        'kind': 'read',
        'status': 'completed',
      });
      peer.emitUpdate(<String, Object?>{
        'sessionUpdate': 'plan',
        'entries': <Object?>[
          <String, Object?>{'content': 'Inspect code', 'status': 'completed'},
        ],
      });
      await Future<void>.delayed(Duration.zero);

      // Assert
      expect(events.whereType<AgentMessageDeltaEvent>().single.delta, 'Hello');
      expect(
        events.whereType<AgentToolCallEvent>().single.toolCall.id,
        'tool-1',
      );
      expect(
        events.whereType<AgentPlanUpdatedEvent>().single.entries.single.content,
        'Inspect code',
      );
    });

    test('rejecting permission responds with server option id', () async {
      // Arrange
      final peer = _FakeCursorPeer();
      final provider = CursorAcpAgentProvider(
        config: AgentProviderConfig.defaultCursor,
        peer: peer,
        sessionIndexStore: MemoryCursorSessionIndexStore(),
      );
      addTearDown(provider.dispose);
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);
      addTearDown(subscription.cancel);
      await provider.startSession(
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
      );

      // Act
      peer.emitPermissionRequest();
      await Future<void>.delayed(Duration.zero);
      final request = events.whereType<AgentPermissionRequestedEvent>().single;
      await provider.respondToPermission(
        AgentPermissionDecision(requestId: request.request.id, approved: false),
      );

      // Assert
      final result = peer.responses.single['result']! as Map<String, Object?>;
      final outcome = result['outcome']! as Map<String, Object?>;
      expect(outcome['optionId'], 'reject-once');
    });

    test('unknown server requests receive method-not-supported', () async {
      // Arrange
      final peer = _FakeCursorPeer();
      final provider = CursorAcpAgentProvider(
        config: AgentProviderConfig.defaultCursor,
        peer: peer,
        sessionIndexStore: MemoryCursorSessionIndexStore(),
      );
      addTearDown(provider.dispose);
      await provider.startSession(
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
      );

      // Act
      peer.emitServerRequest(id: 9, method: 'cursor/unknown');
      await Future<void>.delayed(Duration.zero);

      // Assert
      final error = peer.responses.single['error']! as Map<String, Object?>;
      expect(error['code'], -32601);
    });

    test('switching workspace closes old peer and creates a new one', () async {
      // Arrange
      final peers = <_FakeCursorPeer>[];
      final workspaces = <String>[];
      final provider = CursorAcpAgentProvider(
        config: AgentProviderConfig.defaultCursor,
        peerFactory: (_, workspace) {
          workspaces.add(workspace);
          final peer = _FakeCursorPeer(
            sessionId: 'cursor-session-${peers.length + 1}',
          );
          peers.add(peer);
          return peer;
        },
        sessionIndexStore: MemoryCursorSessionIndexStore(),
      );
      addTearDown(provider.dispose);

      // Act
      await provider.startSession(
        context: const AgentContext(projectPath: r'D:\repo\one'),
      );
      await provider.startSession(
        context: const AgentContext(projectPath: r'D:\repo\two'),
      );

      // Assert
      expect(peers, hasLength(2));
      expect(peers.first.closed, isTrue);
      expect(workspaces[0], isNot(workspaces[1]));
    });

    test(
      'cancel responds to pending permission and notifies session',
      () async {
        // Arrange
        final peer = _FakeCursorPeer();
        final provider = CursorAcpAgentProvider(
          config: AgentProviderConfig.defaultCursor,
          peer: peer,
          sessionIndexStore: MemoryCursorSessionIndexStore(),
        );
        addTearDown(provider.dispose);
        final session = await provider.startSession(
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
        );
        peer.emitPermissionRequest();
        await Future<void>.delayed(Duration.zero);

        // Act
        await provider.cancelTurn(
          AgentTurn(id: 'turn-1', sessionId: session.id),
        );

        // Assert
        expect(peer.notificationsSent, contains('session/cancel'));
        final result = peer.responses.single['result']! as Map<String, Object?>;
        final outcome = result['outcome']! as Map<String, Object?>;
        expect(outcome['outcome'], 'cancelled');
      },
    );

    test('reports an unexpected process exit as unavailable', () async {
      // Arrange
      final peer = _FakeCursorPeer();
      final provider = CursorAcpAgentProvider(
        config: AgentProviderConfig.defaultCursor,
        peer: peer,
        sessionIndexStore: MemoryCursorSessionIndexStore(),
      );
      addTearDown(provider.dispose);
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);
      addTearDown(subscription.cancel);
      await provider.startSession(
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
      );

      // Act
      await peer.simulateUnexpectedExit();
      await Future<void>.delayed(Duration.zero);

      // Assert
      final status = events.whereType<AgentStatusEvent>().last.status;
      expect(status.state, AgentProviderConnectionState.unavailable);
      expect(status.message, contains('意外退出'));
    });

    test('maps session/new JSON-RPC errors to provider error state', () async {
      // Arrange
      final peer = _FakeCursorPeer(sessionNewFails: true);
      final provider = CursorAcpAgentProvider(
        config: AgentProviderConfig.defaultCursor,
        peer: peer,
        sessionIndexStore: MemoryCursorSessionIndexStore(),
      );
      addTearDown(provider.dispose);
      final events = <AgentEvent>[];
      final subscription = provider.events.listen(events.add);
      addTearDown(subscription.cancel);

      // Act / Assert
      await expectLater(
        provider.startSession(
          context: const AgentContext(projectPath: r'D:\repo\zeta'),
        ),
        throwsA(isA<JsonRpcException>()),
      );
      await Future<void>.delayed(Duration.zero);
      final status = events.whereType<AgentStatusEvent>().last.status;
      expect(status.state, AgentProviderConnectionState.error);
      expect(status.message, contains('session'));
    });

    test('indexes new sessions and applies session info metadata', () async {
      // Arrange
      final store = MemoryCursorSessionIndexStore();
      final peer = _FakeCursorPeer();
      final provider = CursorAcpAgentProvider(
        config: AgentProviderConfig.defaultCursor,
        peer: peer,
        sessionIndexStore: store,
        clock: () => DateTime.utc(2026, 7, 14, 1),
      );
      addTearDown(provider.dispose);

      // Act
      await provider.startSession(
        context: const AgentContext(projectPath: r'D:\repo\zeta'),
      );
      peer.emitUpdate(<String, Object?>{
        'sessionUpdate': 'session_info_update',
        'title': 'Cursor history',
        'updatedAt': '2026-07-14T02:00:00Z',
        '_meta': <String, Object?>{
          'branch': 'main',
          'promptText': 'must not persist',
        },
      });
      await _flushAsync();

      // Assert
      final entry = (await store.load()).sessions.single;
      expect(entry.sessionId, 'cursor-session-1');
      expect(entry.title, 'Cursor history');
      expect(entry.updatedAt, DateTime.utc(2026, 7, 14, 2));
      expect(entry.metadata, <String, Object?>{'branch': 'main'});
    });

    test('lists paged local index when session/list is unavailable', () async {
      // Arrange
      final workspace = normalizeCursorWorkspacePath(r'D:\repo\zeta')!;
      final store = MemoryCursorSessionIndexStore(
        CursorSessionIndexSnapshot(
          sessions: <CursorSessionIndexEntry>[
            _indexEntry(
              id: 'session-new',
              workspace: workspace,
              title: 'New thread',
              updatedAt: DateTime.utc(2026, 7, 14, 2),
            ),
            _indexEntry(
              id: 'session-old',
              workspace: workspace,
              title: 'Old thread',
              updatedAt: DateTime.utc(2026, 7, 14, 1),
            ),
          ],
        ),
      );
      final peer = _FakeCursorPeer();
      final provider = CursorAcpAgentProvider(
        config: AgentProviderConfig.defaultCursor,
        peer: peer,
        sessionIndexStore: store,
      );
      addTearDown(provider.dispose);

      // Act
      final first = await provider.listThreads(
        query: const AgentThreadListQuery(
          projectPath: r'D:\repo\zeta\',
          limit: 1,
        ),
      );
      final second = await provider.listThreads(
        query: AgentThreadListQuery(
          projectPath: r'D:\repo\zeta',
          limit: 1,
          cursor: first.nextCursor,
          searchTerm: 'thread',
        ),
      );

      // Assert
      expect(first.threads.single.id, 'session-new');
      expect(first.nextCursor, isNotNull);
      expect(second.threads.single.id, 'session-old');
      expect(peer.requestMethods, isNot(contains('session/list')));
    });

    test('merges session/list with server metadata taking priority', () async {
      // Arrange
      final workspace = normalizeCursorWorkspacePath(r'D:\repo\zeta')!;
      final store = MemoryCursorSessionIndexStore(
        CursorSessionIndexSnapshot(
          sessions: <CursorSessionIndexEntry>[
            _indexEntry(
              id: 'shared-session',
              workspace: workspace,
              title: 'Local title',
              updatedAt: DateTime.utc(2026, 7, 13),
            ),
          ],
        ),
      );
      final peer = _FakeCursorPeer(
        supportsList: true,
        remoteSessions: <Map<String, Object?>>[
          <String, Object?>{
            'sessionId': 'shared-session',
            'cwd': workspace,
            'title': 'Server title',
            'updatedAt': '2026-07-14T03:00:00Z',
          },
          <String, Object?>{
            'sessionId': 'remote-session',
            'cwd': workspace,
            'title': 'Remote only',
            'updatedAt': '2026-07-14T02:00:00Z',
          },
        ],
      );
      final provider = CursorAcpAgentProvider(
        config: AgentProviderConfig.defaultCursor,
        peer: peer,
        sessionIndexStore: store,
      );
      addTearDown(provider.dispose);

      // Act
      final page = await provider.listThreads(
        query: AgentThreadListQuery(projectPath: workspace, limit: 10),
      );

      // Assert
      expect(page.threads, hasLength(2));
      expect(page.threads.first.title, 'Server title');
      expect(peer.requestMethods, contains('session/list'));
    });

    test('captures load replay once and reuses it during resume', () async {
      // Arrange
      final workspace = normalizeCursorWorkspacePath(r'D:\repo\zeta')!;
      final store = MemoryCursorSessionIndexStore(
        CursorSessionIndexSnapshot(
          sessions: <CursorSessionIndexEntry>[
            _indexEntry(
              id: 'cursor-session-1',
              workspace: workspace,
              title: 'Existing',
              updatedAt: DateTime.utc(2026, 7, 14),
            ),
          ],
        ),
      );
      final peer = _FakeCursorPeer(
        loadUpdates: <Map<String, Object?>>[
          <String, Object?>{
            'sessionUpdate': 'user_message_chunk',
            'messageId': 'user-1',
            'content': <String, Object?>{'type': 'text', 'text': 'Question'},
            '_meta': <String, Object?>{'promptId': 'turn-1'},
          },
          <String, Object?>{
            'sessionUpdate': 'agent_message_chunk',
            'messageId': 'agent-1',
            'content': <String, Object?>{'type': 'text', 'text': 'Answer'},
            '_meta': <String, Object?>{'promptId': 'turn-1'},
          },
        ],
      );
      final provider = CursorAcpAgentProvider(
        config: AgentProviderConfig.defaultCursor,
        peer: peer,
        sessionIndexStore: store,
      );
      addTearDown(provider.dispose);

      // Act
      final history = await provider.readThreadHistory(
        threadId: 'cursor-session-1',
        projectPath: workspace,
      );
      peer.emitUpdate(<String, Object?>{
        'sessionUpdate': 'session_info_update',
        'title': 'Updated after replay',
      });
      await _flushAsync();
      final session = await provider.resumeSession(
        'cursor-session-1',
        context: AgentContext(projectPath: workspace),
      );

      // Assert
      expect(history.turns, hasLength(1));
      expect(history.turns.single.entries, hasLength(2));
      expect(session.id, 'cursor-session-1');
      expect(session.title, 'Updated after replay');
      expect(
        peer.requestMethods.where((method) => method == 'session/load'),
        hasLength(1),
      );
    });

    test(
      'load failure is fail-closed and never creates a new session',
      () async {
        // Arrange
        final workspace = normalizeCursorWorkspacePath(r'D:\repo\zeta')!;
        final store = MemoryCursorSessionIndexStore(
          CursorSessionIndexSnapshot(
            sessions: <CursorSessionIndexEntry>[
              _indexEntry(
                id: 'cursor-session-1',
                workspace: workspace,
                updatedAt: DateTime.utc(2026, 7, 14),
              ),
            ],
          ),
        );
        final peer = _FakeCursorPeer(sessionLoadFails: true);
        final provider = CursorAcpAgentProvider(
          config: AgentProviderConfig.defaultCursor,
          peer: peer,
          sessionIndexStore: store,
        );
        addTearDown(provider.dispose);

        // Act / Assert
        await expectLater(
          provider.resumeSession(
            'cursor-session-1',
            context: AgentContext(projectPath: workspace),
          ),
          throwsA(isA<JsonRpcException>()),
        );
        expect(peer.requestMethods, contains('session/load'));
        expect(peer.requestMethods, isNot(contains('session/new')));
        expect((await store.load()).sessions, hasLength(1));
      },
    );

    test('gates remote delete and supports local-only removal', () async {
      // Arrange
      final workspace = normalizeCursorWorkspacePath(r'D:\repo\zeta')!;
      final remoteStore = MemoryCursorSessionIndexStore(
        CursorSessionIndexSnapshot(
          sessions: <CursorSessionIndexEntry>[
            _indexEntry(
              id: 'cursor-session-1',
              workspace: workspace,
              updatedAt: DateTime.utc(2026, 7, 14),
            ),
          ],
        ),
      );
      final peer = _FakeCursorPeer(supportsDelete: true);
      final provider = CursorAcpAgentProvider(
        config: AgentProviderConfig.defaultCursor,
        peer: peer,
        sessionIndexStore: remoteStore,
      );
      addTearDown(provider.dispose);

      // Act
      await provider.deleteThread('cursor-session-1');

      // Assert
      expect(peer.requestMethods, contains('session/delete'));
      expect((await remoteStore.load()).sessions, isEmpty);

      final localStore = MemoryCursorSessionIndexStore(
        CursorSessionIndexSnapshot(
          sessions: <CursorSessionIndexEntry>[
            _indexEntry(
              id: 'local-only',
              workspace: workspace,
              updatedAt: DateTime.utc(2026, 7, 14),
            ),
          ],
        ),
      );
      final localProvider = CursorAcpAgentProvider(
        config: AgentProviderConfig.defaultCursor,
        peer: _FakeCursorPeer(),
        sessionIndexStore: localStore,
      );
      addTearDown(localProvider.dispose);
      await localProvider.removeThreadFromList('local-only');
      expect((await localStore.load()).sessions, isEmpty);
    });
  });
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

CursorSessionIndexEntry _indexEntry({
  required String id,
  required String workspace,
  required DateTime updatedAt,
  String? title,
}) {
  return CursorSessionIndexEntry(
    sessionId: id,
    providerId: cursorAgentProviderId,
    workspacePath: workspace,
    title: title,
    createdAt: updatedAt,
    updatedAt: updatedAt,
  );
}

class _FakeCursorPeer implements JsonRpcPeer {
  _FakeCursorPeer({
    this.sessionId = 'cursor-session-1',
    this.sessionNewFails = false,
    this.sessionLoadFails = false,
    this.supportsList = false,
    this.supportsDelete = false,
    this.remoteSessions = const <Map<String, Object?>>[],
    this.loadUpdates = const <Map<String, Object?>>[],
  });

  final String sessionId;
  final bool sessionNewFails;
  final bool sessionLoadFails;
  final bool supportsList;
  final bool supportsDelete;
  final List<Map<String, Object?>> remoteSessions;
  final List<Map<String, Object?>> loadUpdates;
  final _notifications = StreamController<JsonRpcNotification>.broadcast();
  final _serverRequests = StreamController<JsonRpcRequest>.broadcast();
  final _stderr = StreamController<String>.broadcast();
  final _protocolErrors =
      StreamController<JsonRpcProtocolException>.broadcast();
  final requestMethods = <String>[];
  final requestParams = <Object?>[];
  final responses = <Map<String, Object?>>[];
  final notificationsSent = <String>[];
  bool closed = false;
  bool notificationsClosed = false;

  @override
  Stream<JsonRpcNotification> get notifications => _notifications.stream;

  @override
  Stream<JsonRpcRequest> get serverRequests => _serverRequests.stream;

  @override
  Stream<String> get stderrLines => _stderr.stream;

  @override
  Stream<JsonRpcProtocolException> get protocolErrors => _protocolErrors.stream;

  @override
  Future<void> start() async {}

  @override
  Future<Object?> sendRequest(
    String method, {
    Object? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    requestMethods.add(method);
    requestParams.add(params);
    if (method == 'initialize') {
      return <String, Object?>{
        'protocolVersion': 1,
        'agentInfo': <String, Object?>{
          'name': 'cursor-agent',
          'title': 'Cursor Agent',
          'version': '1.0.0',
        },
        'agentCapabilities': <String, Object?>{
          'loadSession': true,
          'promptCapabilities': <String, Object?>{
            'image': false,
            'embeddedContext': false,
          },
          if (supportsList || supportsDelete)
            'sessionCapabilities': <String, Object?>{
              if (supportsList) 'list': <String, Object?>{},
              if (supportsDelete) 'delete': <String, Object?>{},
            },
        },
        'authMethods': <Object?>[
          <String, Object?>{'id': 'cursor_login', 'name': 'Cursor Login'},
        ],
      };
    }
    if (method == 'authenticate') {
      return <String, Object?>{};
    }
    if (method == 'session/new') {
      if (sessionNewFails) {
        throw const JsonRpcException(
          JsonRpcError(code: -32000, message: 'session failed'),
        );
      }
      return <String, Object?>{'sessionId': sessionId};
    }
    if (method == 'session/load') {
      if (sessionLoadFails) {
        throw const JsonRpcException(
          JsonRpcError(code: -32000, message: 'load failed'),
        );
      }
      for (final update in loadUpdates) {
        emitUpdate(update);
      }
      // ACP replay 必须在 session/load response 前送达。
      await Future<void>.delayed(Duration.zero);
      return <String, Object?>{};
    }
    if (method == 'session/list') {
      return <String, Object?>{'sessions': remoteSessions};
    }
    if (method == 'session/delete') {
      return <String, Object?>{};
    }
    if (method == 'session/prompt') {
      return <String, Object?>{'stopReason': 'end_turn'};
    }
    return <String, Object?>{};
  }

  Map<String, Object?> paramsFor(String method) {
    final index = requestMethods.indexOf(method);
    return requestParams[index]! as Map<String, Object?>;
  }

  @override
  void sendNotification(String method, {Object? params}) {
    notificationsSent.add(method);
  }

  @override
  Future<void> sendResponse(
    Object id, {
    Object? result,
    JsonRpcError? error,
  }) async {
    responses.add(<String, Object?>{
      'id': id,
      'result': ?result,
      if (error != null) 'error': error.toJson(),
    });
  }

  @override
  Future<void> close() async {
    if (closed) {
      return;
    }
    closed = true;
    if (!notificationsClosed) {
      notificationsClosed = true;
      await _notifications.close();
    }
    await _serverRequests.close();
    await _stderr.close();
    await _protocolErrors.close();
  }

  void emitUpdate(Map<String, Object?> update) {
    _notifications.add(
      JsonRpcNotification(
        method: 'session/update',
        params: <String, Object?>{'sessionId': sessionId, 'update': update},
        raw: update,
      ),
    );
  }

  Future<void> simulateUnexpectedExit() async {
    closed = true;
    notificationsClosed = true;
    await _notifications.close();
    await _serverRequests.close();
    await _stderr.close();
    await _protocolErrors.close();
  }

  void emitPermissionRequest() {
    emitServerRequest(
      id: 42,
      method: 'session/request_permission',
      params: <String, Object?>{
        'sessionId': sessionId,
        'toolCall': <String, Object?>{
          'toolCallId': 'tool-1',
          'title': 'Run command',
        },
        'options': <Object?>[
          <String, Object?>{
            'optionId': 'allow-once',
            'name': 'Allow once',
            'kind': 'allow_once',
          },
          <String, Object?>{
            'optionId': 'reject-once',
            'name': 'Reject',
            'kind': 'reject_once',
          },
        ],
      },
    );
  }

  void emitServerRequest({
    required Object id,
    required String method,
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    _serverRequests.add(
      JsonRpcRequest(id: id, method: method, params: params, raw: params),
    );
  }
}
