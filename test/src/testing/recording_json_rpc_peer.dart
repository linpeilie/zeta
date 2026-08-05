import 'dart:async';

import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

/// 一次由测试 harness 捕获的真实 JSON-RPC 请求。
final class RecordedJsonRpcCall {
  const RecordedJsonRpcCall({required this.method, required this.params});

  final String method;
  final Object? params;

  Map<String, Object?> get paramsMap {
    final value = params;
    if (value is Map<String, Object?>) {
      return value;
    }
    return const <String, Object?>{};
  }
}

/// 记录 adapter 实际发出的 JSON-RPC 参数，并返回最小合法协议响应。
///
/// 该 harness 只用于跨 ViewModel / adapter 契约测试，不模拟 production 状态机。
final class RecordingJsonRpcPeer implements JsonRpcPeer {
  final StreamController<JsonRpcNotification> _notifications =
      StreamController<JsonRpcNotification>.broadcast();
  final StreamController<JsonRpcRequest> _serverRequests =
      StreamController<JsonRpcRequest>.broadcast();
  final StreamController<String> _stderrLines =
      StreamController<String>.broadcast();
  final StreamController<JsonRpcProtocolException> _protocolErrors =
      StreamController<JsonRpcProtocolException>.broadcast();

  final List<RecordedJsonRpcCall> calls = <RecordedJsonRpcCall>[];
  final List<RecordedJsonRpcCall> notificationsSent = <RecordedJsonRpcCall>[];

  var _threadSequence = 0;
  var _turnSequence = 0;
  bool _closed = false;

  @override
  Stream<JsonRpcNotification> get notifications => _notifications.stream;

  @override
  Stream<JsonRpcRequest> get serverRequests => _serverRequests.stream;

  @override
  Stream<String> get stderrLines => _stderrLines.stream;

  @override
  Stream<JsonRpcProtocolException> get protocolErrors => _protocolErrors.stream;

  List<RecordedJsonRpcCall> callsFor(String method) {
    return List<RecordedJsonRpcCall>.unmodifiable(
      calls.where((call) => call.method == method),
    );
  }

  RecordedJsonRpcCall callForThread(String method, String threadId) {
    return callsFor(
      method,
    ).singleWhere((call) => call.paramsMap['threadId'] == threadId);
  }

  @override
  Future<void> start() async {}

  @override
  Future<Object?> sendRequest(
    String method, {
    Object? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final snapshot = _freezeJson(params);
    calls.add(RecordedJsonRpcCall(method: method, params: snapshot));
    final paramsMap = snapshot is Map<String, Object?>
        ? snapshot
        : const <String, Object?>{};

    return switch (method) {
      'initialize' => const <String, Object?>{
        'codexHome': '/test/.codex',
        'platformFamily': 'unix',
        'platformOs': 'linux',
        'userAgent': 'codex_cli_rs/0.144.1',
      },
      'collaborationMode/list' => const <String, Object?>{'data': <Object?>[]},
      'skills/list' => const <String, Object?>{'data': <Object?>[]},
      'permissionProfile/list' => const <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': ':read-only',
            'allowed': true,
            'description': 'Read only',
          },
          <String, Object?>{
            'id': ':workspace',
            'allowed': true,
            'description': 'Workspace write',
          },
          <String, Object?>{
            'id': ':danger-full-access',
            'allowed': true,
            'description': 'Full access',
          },
        ],
        'nextCursor': null,
      },
      'thread/start' => <String, Object?>{
        'thread': <String, Object?>{'id': _nextThreadId('started')},
      },
      'thread/resume' => <String, Object?>{
        'thread': <String, Object?>{'id': paramsMap['threadId']},
      },
      'thread/fork' => <String, Object?>{
        'thread': <String, Object?>{
          'id': _nextThreadId('forked'),
          'cwd': paramsMap['cwd'],
          'turns': <Object?>[],
        },
      },
      'thread/read' => <String, Object?>{
        'thread': <String, Object?>{
          'id': paramsMap['threadId'],
          'turns': <Object?>[],
        },
      },
      'thread/unsubscribe' => const <String, Object?>{},
      'turn/start' => <String, Object?>{
        'turn': <String, Object?>{'id': _nextTurnId()},
      },
      'model/list' => const <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': 'gpt-contract',
            'model': 'gpt-contract',
            'displayName': 'Contract model',
            'hidden': false,
            'supportedReasoningEfforts': <Object?>[],
            'defaultReasoningEffort': 'medium',
            'serviceTiers': <Object?>[],
            'defaultServiceTier': null,
            'isDefault': true,
          },
        ],
        'nextCursor': null,
      },
      _ => throw UnsupportedError(
        'RecordingJsonRpcPeer has no response fixture for $method',
      ),
    };
  }

  @override
  void sendNotification(String method, {Object? params}) {
    notificationsSent.add(
      RecordedJsonRpcCall(method: method, params: _freezeJson(params)),
    );
  }

  @override
  Future<void> sendResponse(
    Object id, {
    Object? result,
    JsonRpcError? error,
  }) async {}

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _notifications.close();
    await _serverRequests.close();
    await _stderrLines.close();
    await _protocolErrors.close();
  }

  String _nextThreadId(String prefix) {
    _threadSequence += 1;
    return '$prefix-thread-$_threadSequence';
  }

  String _nextTurnId() {
    _turnSequence += 1;
    return 'turn-$_turnSequence';
  }
}

/// 始终返回同一运行实例，用于验证应用级共享 Provider。
final class FixedAgentProviderFactory implements AgentProviderFactory {
  const FixedAgentProviderFactory(this.provider);

  final AgentProvider provider;

  @override
  AgentProvider create(AgentProviderConfig config) => provider;
}

Object? _freezeJson(Object? value) {
  return switch (value) {
    final Map<Object?, Object?> map => Map<String, Object?>.unmodifiable(
      map.map((key, item) => MapEntry(key.toString(), _freezeJson(item))),
    ),
    final List<Object?> values => List<Object?>.unmodifiable(
      values.map(_freezeJson),
    ),
    _ => value,
  };
}
