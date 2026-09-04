# zeta_agent_provider_sdk

Zeta Agent Provider 插件的共享机制包，承载无厂商语义的 transport、ACP codec、payload 辅助工具与可复用测试契约。

依赖方向固定为：

```text
zeta_agent_provider_sdk
  -> zeta_agent_core
  -> zeta_agent_provider_api
  -> zeta_plugin_kernel
  -> zeta_foundation
```

生产代码不得依赖具体 `zeta_agent_provider_<x>` 包、Zeta 根应用或 Flutter。桌面 CLI 机制允许使用 `dart:io`。

生产机制从 `zeta_agent_provider_sdk.dart` 导入；仅测试使用的契约套件和辅助件从 `zeta_agent_provider_sdk_testing.dart` 导入，主 barrel 不导出 testing 实现。
