import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// IDE 统一弹窗入口。
///
/// 当前委托给 `shadcn_flutter`，以确保 overlay、对齐和过渡效果一致；
/// 后续若切换 UI 库，只需在这一层替换实现。
Future<T?> showIdeDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useRootNavigator = true,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  AlignmentGeometry? alignment,
  bool fullScreen = false,
}) {
  return sf.showDialog<T>(
    context: context,
    builder: builder,
    useRootNavigator: useRootNavigator,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    traversalEdgeBehavior: traversalEdgeBehavior,
    alignment: alignment,
    fullScreen: fullScreen,
  );
}

/// 统一弹窗 action 语义，避免调用方直接依赖某个 UI 库的按钮组件。
enum IdeDialogActionVariant { secondary, primary, destructive }

/// 弹窗操作按钮配置。
class IdeDialogAction {
  const IdeDialogAction({
    required this.label,
    required this.onPressed,
    this.variant = IdeDialogActionVariant.secondary,
  });

  const IdeDialogAction.cancel({this.label = '取消', required this.onPressed})
    : variant = IdeDialogActionVariant.secondary;

  const IdeDialogAction.confirm({this.label = '确认', required this.onPressed})
    : variant = IdeDialogActionVariant.primary;

  const IdeDialogAction.destructive({
    required this.label,
    required this.onPressed,
  }) : variant = IdeDialogActionVariant.destructive;

  final String label;
  final VoidCallback? onPressed;
  final IdeDialogActionVariant variant;
}

/// IDE 统一弹窗壳。
///
/// 内容区仍允许调用方传入任意 widget，但弹窗容器和默认按钮渲染集中在这里，
/// 降低业务层对底层 UI 组件的直接耦合。
class IdeDialog extends StatelessWidget {
  const IdeDialog({
    super.key,
    this.leading,
    this.trailing,
    this.title,
    this.content,
    this.actions = const <IdeDialogAction>[],
    this.surfaceBlur,
    this.surfaceOpacity,
    this.barrierColor,
    this.padding,
  });

  final Widget? leading;
  final Widget? trailing;
  final Widget? title;
  final Widget? content;
  final List<IdeDialogAction> actions;
  final double? surfaceBlur;
  final double? surfaceOpacity;
  final Color? barrierColor;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return sf.AlertDialog(
      leading: leading,
      trailing: trailing,
      title: title,
      content: content,
      surfaceBlur: surfaceBlur,
      surfaceOpacity: surfaceOpacity,
      barrierColor: barrierColor,
      padding: padding,
      actions: actions.isEmpty
          ? null
          : actions.map<Widget>(_buildAction).toList(growable: false),
    );
  }

  Widget _buildAction(IdeDialogAction action) {
    final child = Text(action.label);
    return switch (action.variant) {
      IdeDialogActionVariant.primary => sf.PrimaryButton(
        onPressed: action.onPressed,
        child: child,
      ),
      IdeDialogActionVariant.destructive => sf.DestructiveButton(
        onPressed: action.onPressed,
        child: child,
      ),
      IdeDialogActionVariant.secondary => sf.OutlineButton(
        onPressed: action.onPressed,
        child: child,
      ),
    };
  }
}
