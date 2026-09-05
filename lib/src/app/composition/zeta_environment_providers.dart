import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
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
/// null 表示由首页用自己的默认探测（会扫本机 CLI）。widget test 由
/// `zetaTestComposition` 换成空列表 stub，避免真的去初始化 Agent Management。
final homeProviderDetectionLoaderProvider =
    Provider<HomeProviderDetectionLoader?>(
      (ref) => null,
      name: 'homeProviderDetectionLoader',
    );

/// Provider 可用性探测；null 表示由首页用自己的默认实现。
final agentProviderAvailabilityLoaderProvider =
    Provider<AgentProviderAvailabilityLoader?>(
      (ref) => null,
      name: 'agentProviderAvailabilityLoader',
    );
