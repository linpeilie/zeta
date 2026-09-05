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

管理共用的版本比较、配置/日志脱敏与用量扫描缓存位于 SDK；宿主与插件共用的底层纯文本脱敏和 HOME 环境解析位于 foundation。测试入口另提供中立内存用量分区仓库，插件测试不依赖根测试文件。
