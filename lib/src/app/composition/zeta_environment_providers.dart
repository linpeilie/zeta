import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/app/composition/zeta_host_mode.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/ui/core/system_file_manager.dart';

/// 首页可用 Provider 列表的探测端口。
typedef AgentProviderAvailabilityLoader =
    Future<List<AgentProviderConfig>> Function();

/// 首页本机已安装 Agent 的探测端口。
typedef HomeProviderDetectionLoader = Future<List<ManagedAgent>> Function();

/// 打开项目所在目录的方式。
final projectLocationOpenerProvider = Provider<ProjectLocationOpener>(
  (ref) => openPathInSystemFileManager,
  name: 'projectLocationOpener',
);

/// 首页的本机 Provider 探测。
///
/// null 表示由首页用自己的默认探测；ephemeral 宿主换成"一个都没装"的结果，
/// 避免 widget test 去扫本机 CLI（`ZetaHostMode` 第 2 条硬约束）。
final homeProviderDetectionLoaderProvider =
    Provider<HomeProviderDetectionLoader?>(
      (ref) => ref.watch(zetaHostModeProvider).allowsLocalCliAccess
          ? null
          : _loadNoInstalledHomeProviders,
      name: 'homeProviderDetectionLoader',
    );

/// Provider 可用性探测；null 表示由首页用自己的默认实现。
final agentProviderAvailabilityLoaderProvider =
    Provider<AgentProviderAvailabilityLoader?>(
      (ref) => null,
      name: 'agentProviderAvailabilityLoader',
    );

Future<List<ManagedAgent>> _loadNoInstalledHomeProviders() async =>
    const <ManagedAgent>[];
