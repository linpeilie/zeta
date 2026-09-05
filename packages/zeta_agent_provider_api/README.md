# zeta_agent_provider_api

纯 Dart 的中立插件装配契约，依赖 core、kernel 与 foundation。

- Provider definition/catalog 与 bundle 工厂贡献。
- management：管理定义、能力、检测/配置/日志端口与文案目录；宿主模型缓存只通过 `AgentManagementModelCatalogPort.load` 借用。
- usage：查询/记录/source、JSON-safe 不透明分区与五个文案成员；`AgentUsagePartitionPort` 不暴露宿主存储或路径。

API 不依赖 Flutter、Riverpod、dart:io 或厂商实现。管理默认文案与用量来源默认文案保持迁移前原值。报表、页面时间窗与应用状态仍由根应用拥有。
