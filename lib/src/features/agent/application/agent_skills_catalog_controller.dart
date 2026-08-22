import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Skill 目录加载状态。
enum AgentSkillsLoadStatus {
  /// 当前 Provider 不支持 skill。
  unavailable,

  /// 正在拉取目录。
  loading,

  /// 已取得可用目录（可能为空）。
  ready,

  /// 拉取失败，可重试。
  error,
}

/// Composer / picker 消费的不可变 Skill 目录状态。
@immutable
final class AgentSkillsCatalogState {
  // catalog 为运行时不可变快照，不能做成编译期 const。
  // ignore: prefer_const_constructors_in_immutables
  AgentSkillsCatalogState({
    required this.status,
    required this.catalog,
    this.errorMessage,
    this.providerId,
    this.projectPath,
  });

  final AgentSkillsLoadStatus status;
  final AgentSkillsCatalog catalog;
  final String? errorMessage;
  final String? providerId;
  final String? projectPath;

  List<AgentSkillMetadata> query(String rawQuery) => catalog.query(rawQuery);

  @override
  bool operator ==(Object other) =>
      other is AgentSkillsCatalogState &&
      other.status == status &&
      other.catalog == catalog &&
      other.errorMessage == errorMessage &&
      other.providerId == providerId &&
      other.projectPath == projectPath;

  @override
  int get hashCode =>
      Object.hash(status, catalog, errorMessage, providerId, projectPath);
}

/// 编排 Skill 目录的 stale-while-revalidate 与失效刷新。
final class AgentSkillsCatalogController extends ChangeNotifier {
  AgentSkillsCatalogState _state = AgentSkillsCatalogState(
    status: AgentSkillsLoadStatus.unavailable,
    catalog: AgentSkillsCatalog.empty,
  );

  AgentSkillsPort? _port;
  StreamSubscription<void>? _changedSubscription;
  Future<void>? _inFlight;
  String? _inFlightKey;
  int _generation = 0;
  bool _disposed = false;

  AgentSkillsCatalogState get state => _state;

  bool get canUseSkills =>
      _state.status == AgentSkillsLoadStatus.ready ||
      _state.status == AgentSkillsLoadStatus.loading ||
      _state.status == AgentSkillsLoadStatus.error;

  List<AgentSkillMetadata> query(String rawQuery) => _state.query(rawQuery);

  /// 绑定 Provider 端口与工作区；[port] 为空时标记 unavailable。
  Future<void> bind({
    required String? providerId,
    required String? projectPath,
    required AgentSkillsPort? port,
    String? configFingerprint,
  }) async {
    if (_disposed) {
      return;
    }
    final normalizedProject = _normalizePath(projectPath);
    final key = _cacheKey(
      providerId: providerId,
      projectPath: normalizedProject,
      configFingerprint: configFingerprint,
    );
    final sameBinding =
        _state.providerId == providerId &&
        _state.projectPath == normalizedProject &&
        identical(_port, port);
    if (sameBinding &&
        (_state.status == AgentSkillsLoadStatus.ready ||
            _state.status == AgentSkillsLoadStatus.loading)) {
      return;
    }

    await _changedSubscription?.cancel();
    _changedSubscription = null;
    _port = port;

    if (port == null || providerId == null) {
      _generation += 1;
      _setState(
        AgentSkillsCatalogState(
          status: AgentSkillsLoadStatus.unavailable,
          catalog: AgentSkillsCatalog.empty,
          providerId: providerId,
          projectPath: normalizedProject,
        ),
      );
      return;
    }

    _changedSubscription = port.skillsChanged.listen((_) {
      unawaited(refresh(forceReload: true));
    });

    final keepStale =
        _state.status == AgentSkillsLoadStatus.ready &&
        _state.providerId == providerId &&
        _state.catalog.allSkills.isNotEmpty;
    _setState(
      AgentSkillsCatalogState(
        status: keepStale
            ? AgentSkillsLoadStatus.ready
            : AgentSkillsLoadStatus.loading,
        catalog: keepStale ? _state.catalog : AgentSkillsCatalog.empty,
        providerId: providerId,
        projectPath: normalizedProject,
        errorMessage: null,
      ),
    );
    await _load(
      key: key,
      providerId: providerId,
      projectPath: normalizedProject,
      port: port,
      forceReload: false,
    );
  }

  Future<void> refresh({bool forceReload = true}) async {
    final port = _port;
    final providerId = _state.providerId;
    if (port == null || providerId == null) {
      return;
    }
    final projectPath = _state.projectPath;
    final key = _cacheKey(
      providerId: providerId,
      projectPath: projectPath,
      configFingerprint: null,
    );
    if (_state.status != AgentSkillsLoadStatus.ready) {
      _setState(
        AgentSkillsCatalogState(
          status: AgentSkillsLoadStatus.loading,
          catalog: _state.catalog,
          providerId: providerId,
          projectPath: projectPath,
        ),
      );
    }
    await _load(
      key: key,
      providerId: providerId,
      projectPath: projectPath,
      port: port,
      forceReload: forceReload,
    );
  }

  Future<void> _load({
    required String key,
    required String providerId,
    required String? projectPath,
    required AgentSkillsPort port,
    required bool forceReload,
  }) async {
    final generation = ++_generation;
    if (_inFlight != null && _inFlightKey == key && !forceReload) {
      await _inFlight;
      return;
    }

    final operation = () async {
      try {
        final cwds = <String>[
          if (projectPath != null && projectPath.isNotEmpty) projectPath,
        ];
        final catalog = await port.listSkills(
          cwds: cwds,
          forceReload: forceReload,
        );
        if (_disposed || generation != _generation) {
          return;
        }
        _setState(
          AgentSkillsCatalogState(
            status: AgentSkillsLoadStatus.ready,
            catalog: catalog,
            providerId: providerId,
            projectPath: projectPath,
          ),
        );
      } catch (error) {
        if (_disposed || generation != _generation) {
          return;
        }
        _setState(
          AgentSkillsCatalogState(
            status: AgentSkillsLoadStatus.error,
            catalog: _state.catalog,
            errorMessage: error.toString(),
            providerId: providerId,
            projectPath: projectPath,
          ),
        );
      }
    }();

    _inFlight = operation;
    _inFlightKey = key;
    try {
      await operation;
    } finally {
      if (identical(_inFlight, operation)) {
        _inFlight = null;
        _inFlightKey = null;
      }
    }
  }

  void _setState(AgentSkillsCatalogState next) {
    if (_disposed || _state == next) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  static String _cacheKey({
    required String? providerId,
    required String? projectPath,
    required String? configFingerprint,
  }) {
    return <String?>[providerId, projectPath, configFingerprint].join('\u0001');
  }

  static String? _normalizePath(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    unawaited(_changedSubscription?.cancel());
    _changedSubscription = null;
    _port = null;
    super.dispose();
  }
}
