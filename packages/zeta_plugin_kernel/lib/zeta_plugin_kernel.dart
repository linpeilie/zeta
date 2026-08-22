/// Zeta 的可信插件微内核。
///
/// 这里**只有机制**：注册、依赖拓扑、激活/关闭顺序、状态目录和贡献分发。
///
/// 明确不做的事：
///
/// - 不 import 任何具体插件或 Provider，也不按 ID/显示名分支；
/// - 不加载第三方代码、不扫描目录、不做动态下载或沙箱；
/// - 不持有 Widget、`BuildContext`、`ProviderContainer` 或文件系统入口。
library;

export 'src/plugin_contracts.dart';
export 'src/plugin_registry.dart';
