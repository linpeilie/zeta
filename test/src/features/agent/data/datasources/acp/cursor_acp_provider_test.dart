import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_acp_agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('CursorAcpAgentProvider', () {
    test('requires a workspace before initialize', () async {
      // Arrange
      final provider = CursorAcpAgentProvider(
        config: AgentProviderConfig.defaultCursor,
        peer: _FakeCursorPeer(),
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
  });
}

class _FakeCursorPeer implements JsonRpcPeer {
  _FakeCursorPeer({
    this.sessionId = 'cursor-session-1',
    this.sessionNewFails = false,
  });

  final String sessionId;
  final bool sessionNewFails;
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
    return switch (method) {
      'initialize' => <String, Object?>{
        'protocolVersion': 1,
        'agentInfo': <String, Object?>{
          'name': 'cursor-agent',
          'title': 'Cursor Agent',
          'version': '1.0.0',
        },
        'agentCapabilities': <String, Object?>{
          'promptCapabilities': <String, Object?>{
            'image': false,
            'embeddedContext': false,
          },
        },
        'authMethods': <Object?>[
          <String, Object?>{'id': 'cursor_login', 'name': 'Cursor Login'},
        ],
      },
      'authenticate' => <String, Object?>{},
      'session/new' =>
        sessionNewFails
            ? throw const JsonRpcException(
                JsonRpcError(code: -32000, message: 'session failed'),
              )
            : <String, Object?>{'sessionId': sessionId},
      'session/prompt' => <String, Object?>{'stopReason': 'end_turn'},
      _ => <String, Object?>{},
    };
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
