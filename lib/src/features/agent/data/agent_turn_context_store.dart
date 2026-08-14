import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/core/storage/atomic_text_file.dart';
import 'package:zeta/src/features/agent/data/agent_turn_context_codec.dart';
import 'package:zeta/src/features/agent/domain/agent_turn_context_models.dart';

final _log = loggerFor('zeta.agent.turn_context');

/// Zeta 发起 turn 时记录的会话上下文存储边界。
abstract interface class AgentTurnContextStore {
  Future<AgentThreadTurnContext?> load({
    required String providerId,
    required String threadId,
  });

  Future<void> save(AgentThreadTurnContext context);
}

/// 不落盘的会话上下文，供测试和无文件持久化宿主使用。
final class MemoryAgentTurnContextStore implements AgentTurnContextStore {
  MemoryAgentTurnContextStore({
    Map<String, AgentThreadTurnContext> contexts =
        const <String, AgentThreadTurnContext>{},
  }) : _contexts = <String, AgentThreadTurnContext>{...contexts};

  final Map<String, AgentThreadTurnContext> _contexts;

  @override
  Future<AgentThreadTurnContext?> load({
    required String providerId,
    required String threadId,
  }) async {
    return _contexts[_key(providerId, threadId)];
  }

  @override
  Future<void> save(AgentThreadTurnContext context) async {
    _contexts[_key(context.providerId, context.threadId)] = context;
  }
}

/// `~/.zeta/state/session/<providerId>/<threadId>.json` 的版本化文件存储。
///
/// JSON 只保存白名单 turn 元数据；损坏或未知版本视为缺失，不阻断打开会话。
final class FileAgentTurnContextStore implements AgentTurnContextStore {
  FileAgentTurnContextStore({required this._rootDirectory});

  final Directory _rootDirectory;
  final Map<String, AtomicTextFile> _files = <String, AtomicTextFile>{};
  final Map<String, Future<void>> _writeTails = <String, Future<void>>{};

  @override
  Future<AgentThreadTurnContext?> load({
    required String providerId,
    required String threadId,
  }) async {
    final file = _fileFor(providerId, threadId);
    if (file == null) {
      return null;
    }
    try {
      final source = await file.read();
      if (source == null || source.trim().isEmpty) {
        return null;
      }
      final decoded = tryDecodeAgentThreadTurnContext(jsonDecode(source));
      if (decoded == null) {
        return null;
      }
      if (decoded.providerId != providerId.trim() ||
          decoded.threadId != threadId.trim()) {
        return null;
      }
      return decoded;
    } catch (error) {
      _log.w('Could not load Agent turn context (${error.runtimeType})');
      return null;
    }
  }

  @override
  Future<void> save(AgentThreadTurnContext context) {
    final file = _fileFor(context.providerId, context.threadId);
    if (file == null) {
      _log.w('Skipped Agent turn context save because path is unsafe');
      return Future<void>.value();
    }
    final key = file.file.path;
    final previous = _writeTails[key] ?? Future<void>.value();
    final operation = previous.then((_) async {
      await file.write(jsonEncode(encodeAgentThreadTurnContext(context)));
    });
    _writeTails[key] = operation.catchError((Object _) {});
    return operation;
  }

  AtomicTextFile? _fileFor(String providerId, String threadId) {
    final providerSegment = encodeAgentTurnContextPathSegment(providerId);
    final threadSegment = encodeAgentTurnContextPathSegment(threadId);
    if (providerSegment == null || threadSegment == null) {
      return null;
    }
    final path =
        '${_rootDirectory.path}${Platform.pathSeparator}'
        '$providerSegment${Platform.pathSeparator}'
        '$threadSegment.json';
    return _files.putIfAbsent(path, () => AtomicTextFile(File(path)));
  }
}

String _key(String providerId, String threadId) =>
    '${providerId.trim()}\u0000${threadId.trim()}';

/// 将 providerId / threadId 编码为安全文件名片段。
String? encodeAgentTurnContextPathSegment(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      trimmed.length > 4096 ||
      trimmed.contains('\n') ||
      trimmed.contains('\r') ||
      trimmed.contains('\u0000')) {
    return null;
  }
  final encoded = Uri.encodeComponent(trimmed);
  if (encoded == '.' || encoded == '..') {
    return null;
  }
  return encoded;
}
