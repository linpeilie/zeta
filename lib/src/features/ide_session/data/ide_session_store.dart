import 'dart:io';

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';

/// IDE 会话状态的旧版 shared_preferences key。
const String sessionStorageKey = 'zeta.ide.session.v1';

abstract class IdeSessionStore {
  Future<IdeSessionState?> load();

  Future<void> save(IdeSessionState state);
}

/// 基于 JSON 文件的 IDE 会话仓库。
class FileIdeSessionStore implements IdeSessionStore {
  FileIdeSessionStore({required this._storage});

  final ZetaTextFile _storage;

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

/// 内存版 IDE 会话仓库。
///
/// 临时宿主模式（widget test / 嵌入宿主）使用：会话在进程内往返，不落盘。
class MemoryIdeSessionStore implements IdeSessionStore {
  MemoryIdeSessionStore([this._state]);

  IdeSessionState? _state;

  @override
  Future<IdeSessionState?> load() async => _state;

  @override
  Future<void> save(IdeSessionState state) async {
    _state = state;
  }
}
