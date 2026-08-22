import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:zeta/src/features/agent/data/claude_code_cli_locator.dart';
import 'package:zeta/src/features/agent/data/cli_command_locator.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_cli_metadata.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_process_starter.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/stream_json_peer.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart'
    show ProcessStarter;
import 'package:zeta/src/features/agent/data/mappers/claude_code_initialize_metadata_mapper.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Metadata 探测失败的稳定分类；不携带 stderr、路径或 Provider 原始响应。
enum ClaudeCodeCliMetadataProbeFailure {
  processUnavailable,
  timeout,
  processExited,
  errorResponse,
  invalidResponse,
  invalidStream,
  transportFailure,
}

/// Claude Code metadata 探测的脱敏异常。
class ClaudeCodeCliMetadataProbeException implements Exception {
  const ClaudeCodeCliMetadataProbeException(this.failure);

  final ClaudeCodeCliMetadataProbeFailure failure;

  @override
  String toString() => 'Claude Code metadata probe failed: ${failure.name}';
}

/// 通过独立、无 Prompt 的 stream-json 进程读取 Claude Code 元数据。
class ClaudeCodeCliMetadataProbe {
  ClaudeCodeCliMetadataProbe({
    required this.config,
    this.timeout = const Duration(seconds: 30),
    this.workingDirectory,
    this.locator,
    this.processStarter,
    String Function()? requestIdFactory,
    this.maxLineBytes = kStreamJsonDefaultMaxLineBytes,
  }) : requestIdFactory = requestIdFactory ?? _randomRequestId;

  final AgentProviderConfig config;
  final Duration timeout;
  final String? workingDirectory;
  final ClaudeCodeCliLocator? locator;
  final ProcessStarter? processStarter;
  final String Function() requestIdFactory;
  final int maxLineBytes;

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
    final resultFuture = completion.future.timeout(
      timeout,
      onTimeout: () => throw const ClaudeCodeCliMetadataProbeException(
        ClaudeCodeCliMetadataProbeFailure.timeout,
      ),
    );
    StreamSubscription<StreamJsonEvent>? eventSubscription;
    StreamSubscription<StreamJsonProtocolException>? errorSubscription;

    try {
      eventSubscription = peer.events.listen(
        (event) =>
            _acceptEvent(event, requestId: requestId, completion: completion),
        onError: (Object error, StackTrace stackTrace) => _completeFailure(
          completion,
          ClaudeCodeCliMetadataProbeFailure.transportFailure,
        ),
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
      return await resultFuture;
    } on ClaudeCodeCliMetadataProbeException {
      rethrow;
    } catch (_) {
      _completeFailure(
        completion,
        ClaudeCodeCliMetadataProbeFailure.transportFailure,
      );
      return await resultFuture;
    } finally {
      await eventSubscription?.cancel();
      await errorSubscription?.cancel();
      try {
        await peer.close();
      } catch (_) {
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
    } catch (_) {
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
