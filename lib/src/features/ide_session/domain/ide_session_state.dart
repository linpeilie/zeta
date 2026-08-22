import 'dart:convert';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';

const int sessionStateVersion = 4;

/// IDE 会话快照。
///
/// 这个对象只记录用户工作区恢复需要的信息：项目列表、文件树展开状态、
/// 当前文件，以及每个项目最近使用的 Agent thread id。
class IdeSessionState {
  const IdeSessionState({
    this.projectPaths = const <String>[],
    this.activeProjectPath,
    this.currentFilePath,
    this.expandedDirectoryPaths = const <String>{},
    this.selectedTreeKey,
    this.activeAgentProviderId,
    this.agentThreadIdsByProject = const <String, String>{},
    this.projectThreadExpansionByProject = const <String, bool>{},
    this.cachedThreadsByProject = const <String, List<AgentThreadSummary>>{},
    this.selectedThreadIdsByProject = const <String, String>{},
    this.projectLastOpenedAtByPath = const <String, DateTime>{},
    this.projectHomeActive = false,
    this.workbenchLayout = const IdeWorkbenchLayoutState(),
  });

  final List<String> projectPaths;
  final String? activeProjectPath;
  final String? currentFilePath;
  final Set<String> expandedDirectoryPaths;
  final String? selectedTreeKey;

  /// 当前会话选择的 Agent provider。
  ///
  /// 用于恢复当前 composer 的 provider；每条 thread 的归属仍以摘要中的
  /// `providerId` 为准。
  final String? activeAgentProviderId;

  /// 每个项目对应的最近 Agent thread id。
  ///
  /// 重新打开项目时可以尝试恢复同一条 Agent 线程。
  final Map<String, String> agentThreadIdsByProject;

  /// 项目下 thread 列表的展开状态。
  final Map<String, bool> projectThreadExpansionByProject;

  /// 项目下 thread 列表的轻量缓存。
  final Map<String, List<AgentThreadSummary>> cachedThreadsByProject;

  /// 每个项目当前选中的 thread id。
  final Map<String, String> selectedThreadIdsByProject;

  /// 项目最近一次成功进入的时间，用于全局首页按 MRU 排序。
  final Map<String, DateTime> projectLastOpenedAtByPath;

  /// 当前活动项目是否停留在不带输入框的项目首页。
  ///
  /// 它用于区分同样没有真实 thread id 的项目首页与新建 Thread 草稿。
  final bool projectHomeActive;

  /// 应用级 Workbench 布局与统计选择偏好。
  final IdeWorkbenchLayoutState workbenchLayout;

  /// 编码成持久化 JSON。
  String encode() => jsonEncode(toJson());

  /// 转成版本化 JSON。
  Map<String, Object?> toJson() {
    final expandedPaths = expandedDirectoryPaths.toList()..sort();
    return <String, Object?>{
      'version': sessionStateVersion,
      'projectPaths': projectPaths,
      'activeProjectPath': activeProjectPath,
      'currentFilePath': currentFilePath,
      'expandedDirectoryPaths': expandedPaths,
      'selectedTreeKey': selectedTreeKey,
      'activeAgentProviderId': activeAgentProviderId,
      'agentThreadIdsByProject': agentThreadIdsByProject,
      'projectThreadExpansionByProject': projectThreadExpansionByProject,
      'cachedThreadsByProject': <String, Object?>{
        for (final entry in cachedThreadsByProject.entries)
          entry.key: entry.value.map((thread) => thread.toJson()).toList(),
      },
      'selectedThreadIdsByProject': selectedThreadIdsByProject,
      'projectLastOpenedAtByPath': <String, String>{
        for (final entry in projectLastOpenedAtByPath.entries)
          entry.key: entry.value.toIso8601String(),
      },
      'projectHomeActive': projectHomeActive,
      'workbench': workbenchLayout.toJson(),
    };
  }

  /// 从持久化 JSON 读取会话状态。
  ///
  /// 旧版本、损坏内容或缺失字段都不会抛错；调用方会得到空状态并继续启动。
  static IdeSessionState? tryDecode(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, Object?>) {
        return const IdeSessionState();
      }

      final version = decoded['version'];
      if (version != 1 &&
          version != 2 &&
          version != 3 &&
          version != sessionStateVersion) {
        return const IdeSessionState();
      }

      return IdeSessionState(
        projectPaths: _stringList(decoded['projectPaths']),
        activeProjectPath: _optionalString(decoded['activeProjectPath']),
        currentFilePath: _optionalString(decoded['currentFilePath']),
        expandedDirectoryPaths: _stringList(
          decoded['expandedDirectoryPaths'],
        ).toSet(),
        selectedTreeKey: _optionalString(decoded['selectedTreeKey']),
        activeAgentProviderId: _optionalString(
          decoded['activeAgentProviderId'],
        ),
        agentThreadIdsByProject: _stringMap(decoded['agentThreadIdsByProject']),
        projectThreadExpansionByProject: _boolMap(
          decoded['projectThreadExpansionByProject'],
        ),
        cachedThreadsByProject: _threadSummaryMap(
          decoded['cachedThreadsByProject'],
        ),
        selectedThreadIdsByProject: _stringMap(
          decoded['selectedThreadIdsByProject'],
        ),
        projectLastOpenedAtByPath: _dateTimeMap(
          decoded['projectLastOpenedAtByPath'],
        ),
        projectHomeActive:
            (version == 3 || version == sessionStateVersion) &&
            decoded['projectHomeActive'] == true,
        workbenchLayout: IdeWorkbenchLayoutState.tryDecode(
          decoded['workbench'],
        ),
      );
    } catch (_) {
      return const IdeSessionState();
    }
  }

  static List<String> _stringList(Object? value) {
    if (value is! List<Object?>) {
      return const <String>[];
    }

    final result = <String>[];
    final seen = <String>{};
    for (final item in value) {
      if (item is String && item.isNotEmpty && seen.add(item)) {
        result.add(item);
      }
    }
    return result;
  }

  static String? _optionalString(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map<String, Object?>) {
      return const <String, String>{};
    }

    final result = <String, String>{};
    for (final entry in value.entries) {
      final item = entry.value;
      if (entry.key.isNotEmpty && item is String && item.isNotEmpty) {
        result[entry.key] = item;
      }
    }
    return result;
  }

  static Map<String, bool> _boolMap(Object? value) {
    if (value is! Map<String, Object?>) {
      return const <String, bool>{};
    }

    final result = <String, bool>{};
    for (final entry in value.entries) {
      final item = entry.value;
      if (entry.key.isNotEmpty && item is bool) {
        result[entry.key] = item;
      }
    }
    return result;
  }

  static Map<String, DateTime> _dateTimeMap(Object? value) {
    if (value is! Map<String, Object?>) {
      return const <String, DateTime>{};
    }

    final result = <String, DateTime>{};
    for (final entry in value.entries) {
      final encoded = entry.value;
      if (entry.key.isEmpty) {
        continue;
      }
      try {
        final decoded = switch (encoded) {
          final String value => DateTime.tryParse(value),
          final int value => DateTime.fromMillisecondsSinceEpoch(value),
          _ => null,
        };
        if (decoded != null) {
          result[entry.key] = decoded;
        }
      } on ArgumentError {
        // 单个损坏时间字段不应让整个 IDE 会话失效。
      }
    }
    return result;
  }

  static Map<String, List<AgentThreadSummary>> _threadSummaryMap(
    Object? value,
  ) {
    if (value is! Map<String, Object?>) {
      return const <String, List<AgentThreadSummary>>{};
    }

    final result = <String, List<AgentThreadSummary>>{};
    for (final entry in value.entries) {
      final item = entry.value;
      if (entry.key.isEmpty || item is! List<Object?>) {
        continue;
      }
      final threads = <AgentThreadSummary>[];
      for (final threadJson in item) {
        final thread = AgentThreadSummary.tryDecode(threadJson);
        if (thread != null) {
          threads.add(thread);
        }
      }
      if (threads.isNotEmpty) {
        result[entry.key] = List<AgentThreadSummary>.unmodifiable(threads);
      }
    }
    return result;
  }
}
