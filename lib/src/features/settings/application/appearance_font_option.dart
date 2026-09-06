import 'package:meta/meta.dart';

import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/system_font_family.dart';

/// 字体选择弹窗使用的展示选项。
///
/// 纯 Dart 值对象：目录数据本身由 `SystemFontCatalogService` 拥有，这里只是
/// 展示投影（Phase 3 第 1 批从 controller 文件迁出，切片状态与设置页共用）。
@immutable
class AppearanceFontOption {
  const AppearanceFontOption({
    required this.choice,
    required this.label,
    this.searchAliases = const <String>[],
  });

  factory AppearanceFontOption.system(SystemFontFamily family) {
    return AppearanceFontOption(
      choice: AppearanceFontChoice.system(family.familyName),
      label: family.displayName,
      searchAliases: family.aliases,
    );
  }

  /// 界面 / 代码字体的「系统默认」选项。
  ///
  /// 展示名由 presentation 用 l10n 覆盖；这里的 [label] 只用于搜索匹配，
  /// 使用连字符避免英文 "System default" 被 "source" 这类子串误命中。
  const AppearanceFontOption.systemDefault()
    : choice = const AppearanceFontChoice.systemDefault(),
      label = 'system-default',
      searchAliases = const <String>['system-default', 'default'];

  final AppearanceFontChoice choice;
  final String label;
  final List<String> searchAliases;

  bool matches(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }
    return label.toLowerCase().contains(normalizedQuery) ||
        searchAliases.any(
          (alias) => alias.toLowerCase().contains(normalizedQuery),
        );
  }
}
