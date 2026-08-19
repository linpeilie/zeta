import 'dart:async';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:json_rpc_transport/json_rpc_transport.dart';
import 'package:test/test.dart';

void main() {
  group('ProviderRuntimeJsonRpcPeer', () {
    test('advances lifecycle and scopes incoming messages', () async {
      final startCompleter = Completer<void>();
      final delegate = _FakeJsonRpcPeer(startCompleter: startCompleter);
      final peer = ProviderRuntimeJsonRpcPeer(
        delegate,
        providerId: 'codex',
        runtimeId: 'runtime-test',
      );
      final notification = peer.notifications.first;
      final request = peer.serverRequests.first;

      final firstStart = peer.start();
      final secondStart = peer.start();
      expect(peer.lifecycleState, AgentProviderLifecycleState.starting);
      startCompleter.complete();
      await Future.wait(<Future<void>>[firstStart, secondStart]);
      expect(peer.lifecycleState, AgentProviderLifecycleState.initializing);
      expect(
        peer.runtimeScope,
        const AgentRuntimeScope(runtimeId: 'runtime-test', connectionEpoch: 1),
      );

      delegate
        ..emitNotification()
        ..emitRequest();
      expect((await notification).runtimeScope, peer.runtimeScope);
      expect((await request).runtimeScope, peer.runtimeScope);
      expect(peer.stderrLines, isA<Stream<String>>());
      expect(peer.protocolErrors, isA<Stream<TransportException>>());

      await peer.sendRequest('initialize');
      peer.sendNotification('initialized');
      await peer.sendResponse('response');
      peer.markReady();
      expect(peer.lifecycleState, AgentProviderLifecycleState.ready);
      await peer.start();
      await peer.close();
      expect(peer.lifecycleState, AgentProviderLifecycleState.closed);
    });

    test('rejects invalid lifecycle transitions and client RPC', () async {
      final delegate = _FakeJsonRpcPeer();
      final peer = ProviderRuntimeJsonRpcPeer(delegate, providerId: 'codex');
      expect(peer.markReady, throwsA(isA<TransportClosed>()));
      await expectLater(
        peer.sendRequest('early'),
        throwsA(isA<TransportClosed>()),
      );
      expect(
        () => peer.sendNotification('early'),
        throwsA(isA<TransportClosed>()),
      );

      await peer.start();
      peer.markReady();
      expect(peer.markReady, throwsStateError);
      peer
        ..beginClosing()
        ..beginClosing();
      expect(peer.lifecycleState, AgentProviderLifecycleState.closing);
      await expectLater(
        peer.sendRequest('late'),
        throwsA(isA<TransportClosed>()),
      );
      expect(delegate.requestMethods, isEmpty);

      final firstClose = peer.close();
      final secondClose = peer.close();
      expect(identical(firstClose, secondClose), isTrue);
      await firstClose;
      expect(delegate.closeCalls, 1);
      await expectLater(peer.start(), throwsA(isA<TransportClosed>()));
    });

    test('allows responses while closing and drains handlers', () async {
      final delegate = _FakeJsonRpcPeer();
      final peer = ProviderRuntimeJsonRpcPeer(delegate, providerId: 'test');
      await peer.start();
      peer.markReady();
      final handlerCompleter = Completer<void>();
      final request = JsonRpcRequest(
        id: 'approval',
        method: 'approval/request',
        params: const <String, Object?>{},
        raw: const <String, Object?>{},
        runtimeScope: peer.runtimeScope,
      );
      final handler = peer.handleServerRequest(
        request,
        (_) => handlerCompleter.future,
      );
      peer.beginClosing();
      await peer.sendScopedResponse(
        request.id,
        runtimeScope: request.runtimeScope,
      );
      await peer.sendResponse('plain');

      var closed = false;
      final close = peer.close().then((_) => closed = true);
      await _flushMicrotasks();
      expect(closed, isFalse);
      handlerCompleter.complete();
      await handler;
      await close;
      expect(delegate.responseIds, <Object>['approval', 'plain']);
    });

    test('rejects missing and stale reverse request scopes', () async {
      final delegate = _FakeJsonRpcPeer();
      final peer = ProviderRuntimeJsonRpcPeer(delegate, providerId: 'grok');
      await peer.start();
      peer.markReady();
      const stale = AgentRuntimeScope(runtimeId: 'stale', connectionEpoch: 1);
      await expectLater(
        peer.sendScopedResponse('id', runtimeScope: stale),
        throwsA(isA<TransportClosed>()),
      );
      await expectLater(
        peer.sendScopedResponse('id', runtimeScope: null),
        throwsA(isA<TransportClosed>()),
      );
      final missingScope = JsonRpcRequest(
        id: 'id',
        method: 'method',
        params: const <String, Object?>{},
        raw: const <String, Object?>{},
      );
      await expectLater(
        peer.handleServerRequest(missingScope, (_) {}),
        throwsA(isA<TransportClosed>()),
      );
      await peer.close();
    });

    test('close waits for an in-flight start and preserves closing', () async {
      final startCompleter = Completer<void>();
      final delegate = _FakeJsonRpcPeer(startCompleter: startCompleter);
      final peer = ProviderRuntimeJsonRpcPeer(delegate, providerId: 'test');
      final start = peer.start();
      var closed = false;
      final close = peer.close().then((_) => closed = true);
      await _flushMicrotasks();
      expect(closed, isFalse);
      startCompleter.complete();
      await start;
      await close;
      expect(peer.lifecycleState, AgentProviderLifecycleState.closed);
    });

    test('start and close failures update lifecycle and propagate', () async {
      final startFailure = _FakeJsonRpcPeer(startError: Exception('start'));
      final failedStartPeer = ProviderRuntimeJsonRpcPeer(
        startFailure,
        providerId: 'test',
      );
      await expectLater(failedStartPeer.start(), throwsException);
      expect(
        failedStartPeer.lifecycleState,
        AgentProviderLifecycleState.failed,
      );
      failedStartPeer.markFailed(
        const AgentRuntimeScope(runtimeId: 'old', connectionEpoch: 1),
      );
      await failedStartPeer.close();

      final closeFailure = _FakeJsonRpcPeer(closeError: Exception('close'));
      final failedClosePeer = ProviderRuntimeJsonRpcPeer(
        closeFailure,
        providerId: 'test',
      );
      await failedClosePeer.start();
      await expectLater(failedClosePeer.close(), throwsException);
      expect(
        failedClosePeer.lifecycleState,
        AgentProviderLifecycleState.closed,
      );
    });

    test('unexpected notification completion marks runtime failed', () async {
      final delegate = _FakeJsonRpcPeer();
      final peer = ProviderRuntimeJsonRpcPeer(delegate, providerId: 'codex');
      await peer.start();
      peer.markReady();
      final subscription = peer.notifications.listen((_) {});
      await delegate.finishNotifications();
      await _flushMicrotasks();
      expect(peer.lifecycleState, AgentProviderLifecycleState.failed);
      await subscription.cancel();
      await peer.close();
    });
  });
}

class _FakeJsonRpcPeer implements JsonRpcPeer {
  _FakeJsonRpcPeer({this.startCompleter, this.startError, this.closeError});

  final Completer<void>? startCompleter;
  final Exception? startError;
  final Exception? closeError;
  final StreamController<JsonRpcNotification> _notifications =
      StreamController<JsonRpcNotification>.broadcast();
  final StreamController<JsonRpcRequest> _requests =
      StreamController<JsonRpcRequest>.broadcast();
  final StreamController<String> _stderr = StreamController<String>.broadcast();
  final StreamController<TransportException> _errors =
      StreamController<TransportException>.broadcast();
  final List<String> requestMethods = <String>[];
  final List<Object> responseIds = <Object>[];
  int closeCalls = 0;

  @override
  Stream<JsonRpcNotification> get notifications => _notifications.stream;

  @override
  Stream<JsonRpcRequest> get serverRequests => _requests.stream;

  @override
  Stream<String> get stderrLines => _stderr.stream;

  @override
  Stream<TransportException> get protocolErrors => _errors.stream;

  @override
  Future<void> start() async {
    await startCompleter?.future;
    if (startError case final error?) {
      throw error;
    }
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

  void emitNotification() {
    _notifications.add(
      JsonRpcNotification(
        method: 'notice',
        params: const <String, Object?>{},
        raw: const <String, Object?>{},
      ),
    );
  }

  void emitRequest() {
    _requests.add(
      JsonRpcRequest(
        id: 1,
        method: 'request',
        params: const <String, Object?>{},
        raw: const <String, Object?>{},
      ),
    );
  }

  Future<void> finishNotifications() => _notifications.close();

  @override
  Future<void> close() async {
    closeCalls += 1;
    if (closeError case final error?) {
      throw error;
    }
    await Future.wait<void>(<Future<void>>[
      if (!_notifications.isClosed) _notifications.close(),
      _requests.close(),
      _stderr.close(),
      _errors.close(),
    ]);
  }
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);
