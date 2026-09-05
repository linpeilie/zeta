/// Provider 插件入口与稳定编译期身份。
library;

export 'codex_plugin.dart';

// WP-C 过渡导出：供 manifest 宿主注入与已登记的 management/usage 调用点使用。
// WP-D 收口后，保留宿主注入类型，其余实现仅经独立 testing barrel 提供。
export 'src/codex_cli_locator.dart' show CodexCliLocator, looksLikeCodexCliPath;
