import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/ui/core/system_file_manager.dart';

/// 首页可用 Provider 列表的探测端口。
typedef AgentProviderAvailabilityLoader =
    Future<List<AgentProviderConfig>> Function();

/// 打开项目所在目录的方式。
final projectLocationOpenerProvider = Provider<ProjectLocationOpener>(
  (ref) => openPathInSystemFileManager,
  name: 'projectLocationOpener',
);

/// Provider 可用性探测；null 表示由首页用自己的默认实现。
final agentProviderAvailabilityLoaderProvider =
    Provider<AgentProviderAvailabilityLoader?>(
      (ref) => null,
      name: 'agentProviderAvailabilityLoader',
    );
