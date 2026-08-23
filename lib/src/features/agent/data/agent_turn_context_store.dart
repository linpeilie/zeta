import 'dart:convert';
import 'dart:io';

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/agent/data/agent_turn_context_codec.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

final _log = zetaLoggerFor('zeta.agent.turn_context');

/// 由宿主注入的原子文件构造器（app 组合层提供 `AtomicTextFile(File(path))`）。
typedef AgentTurnContextStorageFactory = ZetaTextFile Function(String path);

/// `~/.zeta/state/session/<providerId>/<threadId>.json` 的版本化文件存储。
///
/// JSON 只保存白名单 turn 元数据；损坏或未知版本视为缺失，不阻断打开会话。
final class FileAgentTurnContextStore implements AgentTurnContextStore {
  FileAgentTurnContextStore({
    required this._rootDirectory,
    required this._createStorage,
  });

  final Directory _rootDirectory;
  final AgentTurnContextStorageFactory _createStorage;
  final Map<String, ZetaTextFile> _files = <String, ZetaTextFile>{};
  final Map<String, Future<void>> _writeTails = <String, Future<void>>{};

  @override
  Future<AgentThreadTurnContext?> load({
    required String providerId,
    required String threadId,
  }) async {
    final entry = _fileFor(providerId, threadId);
    if (entry == null) {
      return null;
    }
    try {
      final source = await entry.storage.read();
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
    final entry = _fileFor(context.providerId, context.threadId);
    if (entry == null) {
      _log.w('Skipped Agent turn context save because path is unsafe');
      return Future<void>.value();
    }
    final key = entry.path;
    final previous = _writeTails[key] ?? Future<void>.value();
    final operation = previous.then((_) async {
      await entry.storage.write(
        jsonEncode(encodeAgentThreadTurnContext(context)),
      );
    });
    _writeTails[key] = operation.catchError((Object _) {});
    return operation;
  }

  ({String path, ZetaTextFile storage})? _fileFor(
    String providerId,
    String threadId,
  ) {
    final providerSegment = encodeAgentTurnContextPathSegment(providerId);
    final threadSegment = encodeAgentTurnContextPathSegment(threadId);
    if (providerSegment == null || threadSegment == null) {
      return null;
    }
    final path =
        '${_rootDirectory.path}${Platform.pathSeparator}'
        '$providerSegment${Platform.pathSeparator}'
        '$threadSegment.json';
    final storage = _files.putIfAbsent(path, () => _createStorage(path));
    return (path: path, storage: storage);
  }
}

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
