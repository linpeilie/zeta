import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/src/claude_code_cli_locator.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_cli_metadata.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_process_starter.dart';
import 'package:claude_code_client/src/datasources/claude_code/stream_json_peer.dart';
import 'package:claude_code_client/src/mappers/claude_code_initialize_metadata_mapper.dart';
import 'package:json_rpc_transport/json_rpc_transport.dart' show ProcessStarter;

/// Metadata 探测失败的稳定分类；不携带 stderr、路径或 Provider 原始响应。
enum ClaudeCodeCliMetadataProbeFailure {
  /// The `processUnavailable` value.
  processUnavailable,

  /// The `timeout` value.
  timeout,

  /// The `processExited` value.
  processExited,

  /// The `errorResponse` value.
  errorResponse,

  /// The `invalidResponse` value.
  invalidResponse,

  /// The `invalidStream` value.
  invalidStream,

  /// The `transportFailure` value.
  transportFailure,
}

/// Claude Code metadata 探测的脱敏异常。
class ClaudeCodeCliMetadataProbeException implements Exception {
  /// Creates a [ClaudeCodeCliMetadataProbeException].
  const ClaudeCodeCliMetadataProbeException(this.failure);

  /// The `failure` value.
  final ClaudeCodeCliMetadataProbeFailure failure;

  @override
  String toString() => 'Claude Code metadata probe failed: ${failure.name}';
}

/// 通过独立、无 Prompt 的 stream-json 进程读取 Claude Code 元数据。
class ClaudeCodeCliMetadataProbe {
  /// Creates a [ClaudeCodeCliMetadataProbe].
  ClaudeCodeCliMetadataProbe({
    required this.config,
    this.timeout = const Duration(seconds: 30),
    this.workingDirectory,
    this.locator,
    this.processStarter,
    String Function()? requestIdFactory,
    this.maxLineBytes = kStreamJsonDefaultMaxLineBytes,
  }) : requestIdFactory = requestIdFactory ?? _randomRequestId;

  /// The `config` value.
  final AgentProviderConfig config;

  /// The `timeout` value.
  final Duration timeout;

  /// The `workingDirectory` value.
  final String? workingDirectory;

  /// The `locator` value.
  final ClaudeCodeCliLocator? locator;

  /// The `processStarter` value.
  final ProcessStarter? processStarter;

  /// Runs `Function`.
  final String Function() requestIdFactory;

  /// The `maxLineBytes` value.
  final int maxLineBytes;

  /// Runs `probe`.
  Future<ClaudeCodeCliMetadataSnapshot> probe() async {
    if (timeout <= Duration.zero) {
      throw const ClaudeCodeCliMetadataProbeException(
        ClaudeCodeCliMetadataProbeFailure.timeout,
      );
    }

    final command = await _resolveCommand();
    final requestId = requestIdFactory().trim();
    if (requestId.isEmpty) {
      throw const ClaudeCodeCliMetadataProbeException(
        ClaudeCodeCliMetadataProbeFailure.transportFailure,
      );
    }

    final peer = StreamJsonPeer(
      command: command.executable,
      arguments: command.arguments,
      workingDirectory: workingDirectory ?? Directory.systemTemp.path,
      environment: config.environment,
      processStarter: processStarter,
      maxLineBytes: maxLineBytes,
    );
    final completion = Completer<ClaudeCodeCliMetadataSnapshot>();
    StreamSubscription<StreamJsonEvent>? eventSubscription;
    StreamSubscription<StreamJsonProtocolException>? errorSubscription;

    try {
      eventSubscription = peer.events.listen(
        (event) =>
            _acceptEvent(event, requestId: requestId, completion: completion),
        onDone: () => _completeFailure(
          completion,
          ClaudeCodeCliMetadataProbeFailure.processExited,
        ),
      );
      errorSubscription = peer.protocolErrors.listen(
        (_) => _completeFailure(
          completion,
          ClaudeCodeCliMetadataProbeFailure.invalidStream,
        ),
      );

      await peer.start();
      await peer.sendControl(<String, Object?>{
        'type': 'control_request',
        'request_id': requestId,
        'request': const <String, Object?>{'subtype': 'initialize'},
      });
      return await completion.future.timeout(
        timeout,
        onTimeout: () => throw const ClaudeCodeCliMetadataProbeException(
          ClaudeCodeCliMetadataProbeFailure.timeout,
        ),
      );
    } on ClaudeCodeCliMetadataProbeException {
      rethrow;
    } on Object catch (_) {
      throw const ClaudeCodeCliMetadataProbeException(
        ClaudeCodeCliMetadataProbeFailure.transportFailure,
      );
    } finally {
      await eventSubscription?.cancel();
      await errorSubscription?.cancel();
      try {
        await peer.close();
      } on Object catch (_) {
        // 探测结果已经确定；关闭失败不得泄漏原始进程诊断。
      }
    }
  }

  Future<ResolvedCliProcessCommand> _resolveCommand() async {
    try {
      return await resolveClaudeCodeMetadataProbeCommand(
        config,
        locator: locator,
      );
    } on Object catch (_) {
      throw const ClaudeCodeCliMetadataProbeException(
        ClaudeCodeCliMetadataProbeFailure.processUnavailable,
      );
    }
  }
}

void _acceptEvent(
  StreamJsonEvent event, {
  required String requestId,
  required Completer<ClaudeCodeCliMetadataSnapshot> completion,
}) {
  if (completion.isCompleted || event.type != 'control_response') {
    return;
  }
  final envelope = _asMap(event.raw['response']);
  if (envelope == null || envelope['request_id'] != requestId) {
    return;
  }
  if (envelope['subtype'] != 'success') {
    _completeFailure(
      completion,
      ClaudeCodeCliMetadataProbeFailure.errorResponse,
    );
    return;
  }
  if (_asMap(envelope['response']) == null) {
    _completeFailure(
      completion,
      ClaudeCodeCliMetadataProbeFailure.invalidResponse,
    );
    return;
  }
  completion.complete(mapClaudeCodeInitializeMetadata(event.raw));
}

void _completeFailure(
  Completer<ClaudeCodeCliMetadataSnapshot> completion,
  ClaudeCodeCliMetadataProbeFailure failure,
) {
  if (!completion.isCompleted) {
    completion.completeError(ClaudeCodeCliMetadataProbeException(failure));
  }
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

String _randomRequestId() {
  final random = Random.secure();
  final suffix = List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return 'zeta-metadata-$suffix';
}
