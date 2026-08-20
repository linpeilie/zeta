import 'package:app_ui/app_ui.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// Shows a non-adaptive desktop dialog overlay.
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
  return sf
      .showOverlay<T>(
        context,
        sf.DialogConfiguration(
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
        ),
        adaptive: false,
      )
      .future;
}

/// Visual variants for [IdeDialogAction].
enum IdeDialogActionVariant {
  /// Secondary action.
  secondary,

  /// Primary confirmation.
  primary,

  /// Destructive confirmation.
  destructive,
}

/// Immutable dialog-action configuration with caller-supplied copy.
class IdeDialogAction {
  /// Creates an action.
  const IdeDialogAction({
    required this.label,
    required this.onPressed,
    this.variant = IdeDialogActionVariant.secondary,
  });

  /// Creates a cancel action.
  const IdeDialogAction.cancel({
    required this.label,
    required this.onPressed,
  }) : variant = IdeDialogActionVariant.secondary;

  /// Creates a primary confirmation.
  const IdeDialogAction.confirm({
    required this.label,
    required this.onPressed,
  }) : variant = IdeDialogActionVariant.primary;

  /// Creates a destructive confirmation.
  const IdeDialogAction.destructive({
    required this.label,
    required this.onPressed,
  }) : variant = IdeDialogActionVariant.destructive;

  /// Visible action copy.
  final String label;

  /// Activation callback.
  final VoidCallback? onPressed;

  /// Visual variant.
  final IdeDialogActionVariant variant;
}

/// A shadcn dialog shell whose content and copy come from the caller.
class IdeDialog extends StatelessWidget {
  /// Creates a dialog shell.
  const IdeDialog({
    this.leading,
    this.trailing,
    this.title,
    this.content,
    this.actions = const <IdeDialogAction>[],
    this.surfaceBlur,
    this.surfaceOpacity,
    this.barrierColor,
    this.padding,
    super.key,
  });

  /// Optional leading content.
  final Widget? leading;

  /// Optional trailing content.
  final Widget? trailing;

  /// Optional title.
  final Widget? title;

  /// Optional body.
  final Widget? content;

  /// Dialog actions.
  final List<IdeDialogAction> actions;

  /// Optional surface blur.
  final double? surfaceBlur;

  /// Optional surface opacity.
  final double? surfaceOpacity;

  /// Optional barrier color.
  final Color? barrierColor;

  /// Optional content padding.
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
