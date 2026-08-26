import 'package:zeta/src/features/settings/domain/system_font_family.dart';

/// 系统字体目录端口。
///
/// 实现留在 data；application 只依赖本端口，不碰原生通道。
abstract class SystemFontCatalogService {
  /// 界面字体家族。
  Future<List<SystemFontFamily>> uiFontFamilies();

  /// 等宽代码字体家族。
  Future<List<SystemFontFamily>> codeFontFamilies();

  /// 按当前字体目录中的真实家族名解析字体。
  Future<SystemFontFamily?> resolveFontFamily(String name);
}
