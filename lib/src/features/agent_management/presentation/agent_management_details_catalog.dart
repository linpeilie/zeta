import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/agent_management_agent_view.dart';

/// 显示与用户动作的窄端口；原始路径没有字符串读取出口。
abstract interface class AgentManagementDetailsCatalog {
  AgentManagementDetailDisplay display(AgentManagementDetailsHandle? handle);
  Future<void> copyExecutableLocation(AgentManagementDetailsHandle handle);
  Future<void> openExecutableDirectory(AgentManagementDetailsHandle handle);
}

final class AgentManagementDetailDisplay {
  const AgentManagementDetailDisplay({
    required this.available,
    this.executableLocationLabel = '',
    this.diagnosticDescription = '',
  });
  final bool available;
  final String executableLocationLabel;
  final String diagnosticDescription;
}

final agentManagementDetailsCatalogProvider =
    Provider<AgentManagementDetailsCatalog>(
      (ref) => throw StateError('Management detail catalog was not installed'),
    );
