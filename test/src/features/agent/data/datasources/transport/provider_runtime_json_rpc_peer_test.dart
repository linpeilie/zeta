import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/provider_runtime_json_rpc_peer.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('ProviderRuntimeJsonRpcPeer', () {
    test(
      'advances lifecycle and creates a scoped connection identity',
      () async {
        final startCompleter = Completer<void>();
        final delegate = _FakeJsonRpcPeer(startCompleter: startCompleter);
        final peer = ProviderRuntimeJsonRpcPeer(
          delegate,
          providerId: 'codex',
          runtimeId: 'runtime-test',
        );

        final start = peer.start();
        expect(peer.lifecycleState, AgentProviderLifecycleState.starting);

        startCompleter.complete();
        await start;
        expect(peer.lifecycleState, AgentProviderLifecycleState.initializing);
        expect(
          peer.runtimeScope,
          const AgentRuntimeScope(
            runtimeId: 'runtime-test',
            connectionEpoch: 1,
          ),
        );

        await peer.sendRequest('initialize');
        peer.markReady();
        expect(peer.lifecycleState, AgentProviderLifecycleState.ready);

        await peer.close();
        expect(peer.lifecycleState, AgentProviderLifecycleState.closed);
      },
    );

    test('closing rejects new client RPC and dispose is idempotent', () async {
      final delegate = _FakeJsonRpcPeer();
      final peer = ProviderRuntimeJsonRpcPeer(delegate, providerId: 'codex');
      await peer.start();
      peer.markReady();

      peer.beginClosing();
      expect(peer.lifecycleState, AgentProviderLifecycleState.closing);
      await expectLater(
        peer.sendRequest('thread/list'),
        throwsA(isA<ProviderConnectionClosedException>()),
      );
      expect(delegate.requestMethods, isEmpty);

      final firstClose = peer.close();
      final secondClose = peer.close();
      expect(identical(firstClose, secondClose), isTrue);
      await firstClose;
      expect(delegate.closeCalls, 1);
      expect(peer.lifecycleState, AgentProviderLifecycleState.closed);
    });

    test(
      'close waits for an accepted server request handler to drain',
      () async {
        final delegate = _FakeJsonRpcPeer();
        final peer = ProviderRuntimeJsonRpcPeer(
          delegate,
          providerId: 'test-provider',
        );
        await peer.start();
        peer.markReady();
        final handlerCompleter = Completer<void>();
        final request = JsonRpcRequest(
          id: 'approval-1',
          method: 'session/request_permission',
          params: const <String, Object?>{},
          raw: const <String, Object?>{},
          runtimeScope: peer.runtimeScope,
        );
        final handler = peer.handleServerRequest(
          request,
          (_) => handlerCompleter.future,
        );

        var closeCompleted = false;
        final close = peer.close().then((_) => closeCompleted = true);
        await Future<void>.delayed(Duration.zero);
        expect(peer.lifecycleState, AgentProviderLifecycleState.closing);
        expect(closeCompleted, isFalse);

        handlerCompleter.complete();
        await handler;
        await close;
        expect(closeCompleted, isTrue);
        expect(peer.lifecycleState, AgentProviderLifecycleState.closed);
      },
    );

    test('close waits for an in-flight process start to settle', () async {
      final startCompleter = Completer<void>();
      final delegate = _FakeJsonRpcPeer(startCompleter: startCompleter);
      final peer = ProviderRuntimeJsonRpcPeer(
        delegate,
        providerId: 'test-provider',
      );
      final start = peer.start();

      var closeCompleted = false;
      final close = peer.close().then((_) => closeCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(closeCompleted, isFalse);
      expect(peer.lifecycleState, AgentProviderLifecycleState.closing);

      startCompleter.complete();
      await start;
      await close;
      expect(closeCompleted, isTrue);
      expect(peer.lifecycleState, AgentProviderLifecycleState.closed);
    });

    test('unexpected transport completion marks the runtime failed', () async {
      final delegate = _FakeJsonRpcPeer();
      final peer = ProviderRuntimeJsonRpcPeer(delegate, providerId: 'codex');
      await peer.start();
      peer.markReady();
      final subscription = peer.notifications.listen((_) {});

      await delegate.close();
      await Future<void>.delayed(Duration.zero);

      expect(peer.lifecycleState, AgentProviderLifecycleState.failed);
      await subscription.cancel();
    });

    test('rejects a response scoped to a closed connection', () async {
      final delegate = _FakeJsonRpcPeer();
      final peer = ProviderRuntimeJsonRpcPeer(delegate, providerId: 'grok');
      await peer.start();
      peer.markReady();
      final oldScope = peer.runtimeScope;
      await peer.close();

      await expectLater(
        peer.sendScopedResponse('approval-1', runtimeScope: oldScope),
        throwsA(isA<ProviderConnectionClosedException>()),
      );
      expect(delegate.responseIds, isEmpty);
    });
  });
}

class _FakeJsonRpcPeer implements JsonRpcPeer {
  _FakeJsonRpcPeer({this.startCompleter});

  final Completer<void>? startCompleter;
  final StreamController<JsonRpcNotification> _notifications =
      StreamController<JsonRpcNotification>.broadcast();
  final StreamController<JsonRpcRequest> _serverRequests =
      StreamController<JsonRpcRequest>.broadcast();
  final StreamController<String> _stderr = StreamController<String>.broadcast();
  final StreamController<JsonRpcProtocolException> _protocolErrors =
      StreamController<JsonRpcProtocolException>.broadcast();
  final List<String> requestMethods = <String>[];
  final List<Object> responseIds = <Object>[];
  int closeCalls = 0;

  @override
  Stream<JsonRpcNotification> get notifications => _notifications.stream;

  @override
  Stream<JsonRpcRequest> get serverRequests => _serverRequests.stream;

  @override
  Stream<String> get stderrLines => _stderr.stream;

  @override
  Stream<JsonRpcProtocolException> get protocolErrors => _protocolErrors.stream;

  @override
  Future<void> start() async {
    await startCompleter?.future;
  }

  @override
  Future<Object?> sendRequest(
    String method, {
    Object? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    requestMethods.add(method);
    return const <String, Object?>{};
  }

  @override
  void sendNotification(String method, {Object? params}) {}

  @override
  Future<void> sendResponse(
    Object id, {
    Object? result,
    JsonRpcError? error,
  }) async {
    responseIds.add(id);
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    await Future.wait(<Future<void>>[
      _notifications.close(),
      _serverRequests.close(),
      _stderr.close(),
      _protocolErrors.close(),
    ]);
  }
}
