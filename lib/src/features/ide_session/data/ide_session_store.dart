import 'dart:io';

import 'package:zeta/src/core/storage/atomic_text_file.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';

/// IDE 会话状态的旧版 shared_preferences key。
const String sessionStorageKey = 'zeta.ide.session.v1';

abstract class IdeSessionStore {
  Future<IdeSessionState?> load();

  Future<void> save(IdeSessionState state);
}

/// 基于 JSON 文件的 IDE 会话仓库。
class FileIdeSessionStore implements IdeSessionStore {
  FileIdeSessionStore({required File file}) : _storage = AtomicTextFile(file);

  final AtomicTextFile _storage;

  @override
  Future<IdeSessionState?> load() async {
    try {
      return IdeSessionState.tryDecode(await _storage.read());
    } on IOException {
      // 会话文件不可读与首次启动等价，不阻断 IDE 进入空工作区。
      return null;
    } on FormatException {
      // 会话文件不可读与首次启动等价，不阻断 IDE 进入空工作区。
      return null;
    }
  }

  @override
  Future<void> save(IdeSessionState state) async {
    await _storage.write(state.encode());
  }
}

class CallbackIdeSessionStore implements IdeSessionStore {
  const CallbackIdeSessionStore({
    required this.loadJson,
    required this.saveJson,
  });

  final Future<String?> Function() loadJson;
  final Future<void> Function(String value) saveJson;

  @override
  Future<IdeSessionState?> load() async {
    return IdeSessionState.tryDecode(await loadJson());
  }

  @override
  Future<void> save(IdeSessionState state) {
    return saveJson(state.encode());
  }
}
