export 'package:zeta/src/features/agent/application/agent_provider_settings_controller.dart'
    show AgentProviderSettingsController;

import 'package:zeta/src/features/agent/application/agent_provider_settings_controller.dart';

/// 旧 UI 路径的兼容别名；新代码应依赖 application 端口或具体设置控制器。
typedef ActiveAgentProviderController = AgentProviderSettingsController;
