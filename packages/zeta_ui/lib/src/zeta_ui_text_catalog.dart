import 'package:flutter/widgets.dart';

/// 设计系统自有用户可见文案的注入端口。
///
/// `zeta_ui` 是纯设计系统，**不依赖** generated l10n、`AppLocalizations` 或任何
/// 应用侧本地化设施：它只声明自己需要哪些文案，由宿主注入实现。
///
/// 这里只收录**控件自身**必须发出的文案（无障碍标签、tooltip、状态提示）。
/// 业务文案一律由调用方通过参数传入，不得往这里加。
abstract interface class ZetaUiTextCatalog {
  /// 标题栏菜单按钮的无障碍标签。
  String get commonMenu;

  /// 标题栏 Logo 的无障碍标签。
  String get workbenchLogoSemantics;

  /// 工作台浮层关闭按钮的无障碍标签。
  String get workbenchCloseOverlay;

  /// 虚拟滚动条的无障碍标签。
  String get timelineScrollbar;

  /// 滚动到底部按钮的无障碍标签。
  String get timelineScrollToEnd;

  /// 底部有新内容时的提示。
  String get timelineNewContent;

  /// 回到底部的提示。
  String get timelineBackToBottom;

  /// Tab 处于加载态时追加到无障碍标签后的说明。
  String tabsLoadingSuffix(String label);

  /// 线性加载指示器的默认无障碍标签。
  String get loading;

  /// 忙碌指示器的默认无障碍标签。
  String get running;

  /// 窗口最小化按钮。
  String get windowMinimize;

  /// 窗口还原按钮（已最大化时）。
  String get windowRestore;

  /// 窗口最大化按钮。
  String get windowMaximize;

  /// 窗口关闭按钮。
  String get windowClose;
}

/// 未注入宿主目录时使用的英文回退。
///
/// 回退存在的意义是让 `zeta_ui` 可以脱离宿主独立渲染与测试；生产路径必须由
/// 组合层注入真实目录，否则界面语言会与其余部分不一致。
final class FallbackZetaUiTextCatalog implements ZetaUiTextCatalog {
  const FallbackZetaUiTextCatalog();

  @override
  String get commonMenu => 'Menu';

  @override
  String get workbenchLogoSemantics => 'Zeta Logo';

  @override
  String get workbenchCloseOverlay => 'Close workbench overlay';

  @override
  String get timelineScrollbar => 'Conversation scrollbar';

  @override
  String get timelineScrollToEnd => 'Scroll to the end of the conversation';

  @override
  String get timelineNewContent => 'New content';

  @override
  String get timelineBackToBottom => 'Back to bottom';

  @override
  String tabsLoadingSuffix(String label) => '$label, loading';

  @override
  String get loading => 'Loading';

  @override
  String get running => 'Running';

  @override
  String get windowMinimize => 'Minimize';

  @override
  String get windowRestore => 'Restore';

  @override
  String get windowMaximize => 'Maximize';

  @override
  String get windowClose => 'Close';
}

/// 把 [ZetaUiTextCatalog] 注入 Widget 子树。
///
/// 与 [IdeThemeScope] 一样是"宿主在应用根部装一次"的 scope；控件通过
/// [IdeUiText.of] 读取，不感知宿主用的是 ARB、硬编码还是测试 fake。
class IdeUiTextScope extends InheritedWidget {
  const IdeUiTextScope({
    super.key,
    required this.catalog,
    required super.child,
  });

  final ZetaUiTextCatalog catalog;

  @override
  bool updateShouldNotify(IdeUiTextScope oldWidget) =>
      !identical(oldWidget.catalog, catalog);
}

/// 读取当前子树的设计系统文案目录。
abstract final class IdeUiText {
  /// 未注入时返回英文回退，保证控件在任何宿主下都能渲染。
  static ZetaUiTextCatalog of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<IdeUiTextScope>();
    return scope?.catalog ?? const FallbackZetaUiTextCatalog();
  }
}
