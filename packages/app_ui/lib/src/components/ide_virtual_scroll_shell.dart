import 'package:app_ui/app_ui.dart';

/// Composes a virtual scrollbar with an optional scroll-to-end action.
class IdeVirtualScrollShell extends StatelessWidget {
  /// Creates a virtual-scroll shell.
  const IdeVirtualScrollShell({
    required this.controller,
    required this.child,
    required this.scrollbarSemanticLabel,
    required this.scrollToEndSemanticLabel,
    required this.newContentLabel,
    required this.backToBottomLabel,
    this.showScrollToEndButton = false,
    this.hasNewContent = false,
    this.onScrollToEnd,
    super.key,
  });

  /// Controller shared with [child].
  final ScrollController controller;

  /// Scrollable virtual-list content.
  final Widget child;

  /// Localized scrollbar accessible name.
  final String scrollbarSemanticLabel;

  /// Localized scroll-to-end accessible name.
  final String scrollToEndSemanticLabel;

  /// Localized visible label when new content is available.
  final String newContentLabel;

  /// Localized visible label when returning to the end.
  final String backToBottomLabel;

  /// Whether to show the scroll-to-end action.
  final bool showScrollToEndButton;

  /// Whether the action should advertise new content.
  final bool hasNewContent;

  /// Optional scroll-to-end callback.
  final VoidCallback? onScrollToEnd;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final callback = onScrollToEnd;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: IdeVirtualScrollbar(
            controller: controller,
            semanticLabel: scrollbarSemanticLabel,
            child: child,
          ),
        ),
        if (showScrollToEndButton && callback != null)
          PositionedDirectional(
            end: spacing.sm,
            bottom: spacing.sm,
            child: AnimatedOpacity(
              opacity: 1,
              duration: context.appMotion.resolveFor(
                context,
                context.appMotion.fast,
              ),
              child: IdeScrollToEndButton(
                onPressed: callback,
                semanticLabel: scrollToEndSemanticLabel,
                newContentLabel: newContentLabel,
                backToBottomLabel: backToBottomLabel,
                hasNewContent: hasNewContent,
              ),
            ),
          ),
      ],
    );
  }
}

/// Forwards user-originated scroll notifications to [coordinator].
bool dispatchUserScrollToCoordinator({
  required IdeVirtualScrollCoordinator coordinator,
  required ScrollNotification notification,
  required ScrollController controller,
}) {
  if (coordinator.isProgrammatic) return false;

  final isUserDragUpdate =
      notification is ScrollUpdateNotification &&
      notification.dragDetails != null;
  final accepted = notification is UserScrollNotification || isUserDragUpdate;
  if (!accepted || !controller.hasClients) return false;

  final position = controller.position;
  coordinator.onUserScroll(
    IdeVirtualScrollMetricsSnapshot(
      pixels: position.pixels,
      maxScrollExtent: position.maxScrollExtent,
      viewportDimension: position.viewportDimension,
    ),
  );
  return true;
}
