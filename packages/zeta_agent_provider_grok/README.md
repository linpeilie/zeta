# zeta_agent_provider_grok

grok 的独立纯 Dart Provider 插件。生产入口是 `zeta_agent_provider_grok.dart`；宿主测试的实现类型只从独立 `zeta_agent_provider_grok_testing.dart` 入口取得。

依赖方向：本包 → provider_api / provider_sdk / agent_core / plugin_kernel / foundation。禁止反向依赖根应用、其他插件、Flutter 或 Riverpod。

在本包目录运行：

```sh
dart analyze
dart test
# 也可使用 Flutter 测试运行器
flutter test
```

也可在仓库根目录运行 `flutter test packages/zeta_agent_provider_grok`，资源按 package config 定位，不依赖当前目录。

协议测试与脱敏 fixture 随包存放；`contracts_test.dart` 复用 SDK 套件，包含事件回放。根应用通过 `lib/src/app/plugins/agent_provider_manifest.dart` 登记插件。

管理 repository 和用量 source/scanner/codec 随插件提供，激活句柄同时贡献 Provider、management 和 usage。生产 barrel 仅供 manifest 登记及必要的宿主注入；具体实现通过独立 testing barrel 测试。持久化 providerId、providerType 与默认配置逐字保持原值。
