import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// Shows a zoomable image preview using caller-owned image data and copy.
Future<void> showIdeImagePreview(
  BuildContext context, {
  required ImageProvider image,
  required String semanticLabel,
  required String unavailableMessage,
  required String closeSemanticLabel,
  BoxFit fit = BoxFit.contain,
  FilterQuality filterQuality = FilterQuality.medium,
}) async {
  final media = MediaQuery.sizeOf(context);
  final dialogWidth = (media.width * 0.92).clamp(280.0, 960.0);
  final dialogHeight = (media.height * 0.88).clamp(240.0, 720.0);
  final imageHeight = (dialogHeight - 96).clamp(160.0, 640.0);
  await showIdeDialog<void>(
    context: context,
    barrierColor: sf.Colors.black.withValues(alpha: 0.55),
    builder: (dialogContext) => IdeDialog(
      trailing: IdeIconButton(
        icon: Icons.close,
        semanticLabel: closeSemanticLabel,
        variant: IdeButtonVariant.ghost,
        onPressed: () => unawaited(sf.closeOverlay<void>(dialogContext)),
      ),
      content: SizedBox(
        width: dialogWidth,
        height: imageHeight,
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Semantics(
            image: true,
            label: semanticLabel,
            excludeSemantics: true,
            child: Image(
              image: image,
              width: dialogWidth,
              height: imageHeight,
              fit: fit,
              filterQuality: filterQuality,
              errorBuilder: (context, error, stackTrace) => Center(
                child: Text(
                  unavailableMessage,
                  style: context.appTypography.bodySmall.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A pure-UI image thumbnail that can open [showIdeImagePreview].
class IdeImageThumbnail extends StatelessWidget {
  /// Creates a thumbnail with caller-owned image data and localized copy.
  const IdeImageThumbnail({
    required this.image,
    required this.size,
    required this.tooltip,
    required this.semanticLabel,
    required this.unavailableMessage,
    required this.closeSemanticLabel,
    this.borderRadius,
    this.enablePreview = true,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.medium,
    this.error,
    super.key,
  }) : assert(size >= 0, 'size must be non-negative.');

  /// Caller-owned image source; file access remains in the app adapter.
  final ImageProvider image;

  /// Square thumbnail side.
  final double size;

  /// Hover tooltip copy.
  final String tooltip;

  /// Accessible image/action name.
  final String semanticLabel;

  /// Copy shown when preview decoding fails.
  final String unavailableMessage;

  /// Accessible name for the preview close button.
  final String closeSemanticLabel;

  /// Optional corner radius.
  final BorderRadius? borderRadius;

  /// Whether the thumbnail opens a preview.
  final bool enablePreview;

  /// Thumbnail fit.
  final BoxFit fit;

  /// Decode/render quality.
  final FilterQuality filterQuality;

  /// Optional thumbnail error replacement.
  final Widget? error;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? context.appRadii.allSmall;
    final fallback =
        error ??
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.appColors.surfaceElevated,
            borderRadius: radius,
            border: Border.all(color: context.appColors.borderSubtle),
          ),
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                size: size >= 64 ? 20 : 18,
                color: context.appColors.textTertiary,
              ),
            ),
          ),
        );
    final thumbnail = ClipRRect(
      borderRadius: radius,
      child: Image(
        image: image,
        width: size,
        height: size,
        fit: fit,
        filterQuality: filterQuality,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
    if (!enablePreview) {
      return Semantics(
        image: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: thumbnail,
      );
    }
    return IdeTooltip(
      message: tooltip,
      child: PaneInteractiveSurface(
        width: size,
        height: size,
        padding: EdgeInsets.zero,
        semanticLabel: semanticLabel,
        borderRadius: radius,
        onPressed: () => unawaited(
          showIdeImagePreview(
            context,
            image: image,
            semanticLabel: semanticLabel,
            unavailableMessage: unavailableMessage,
            closeSemanticLabel: closeSemanticLabel,
          ),
        ),
        child: thumbnail,
      ),
    );
  }
}
