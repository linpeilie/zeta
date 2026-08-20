import 'package:app_ui/app_ui.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// Semantic tones for toast feedback.
enum IdeToastTone {
  /// Informational feedback.
  info,

  /// Error feedback.
  error,

  /// Success feedback.
  success,
}

/// Shows a live-region desktop toast, or returns null for blank copy.
sf.ToastOverlay? showIdeToast(
  BuildContext context, {
  required String message,
  required String closeSemanticLabel,
  IdeToastTone tone = IdeToastTone.info,
  Duration showDuration = const Duration(seconds: 2),
  sf.ToastLocation location = sf.ToastLocation.bottomRight,
  bool dismissible = true,
}) {
  final trimmed = message.trim();
  if (trimmed.isEmpty) return null;
  return sf.showToast(
    context: context,
    location: location,
    showDuration: showDuration,
    dismissible: dismissible,
    builder: (toastContext, overlay) => _IdeToastCard(
      message: trimmed,
      closeSemanticLabel: closeSemanticLabel,
      tone: tone,
      onClose: overlay.close,
    ),
  );
}

class _IdeToastCard extends StatelessWidget {
  const _IdeToastCard({
    required this.message,
    required this.closeSemanticLabel,
    required this.tone,
    required this.onClose,
  });

  final String message;
  final String closeSemanticLabel;
  final IdeToastTone tone;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final messageColor = switch (tone) {
      IdeToastTone.info => colors.textPrimary,
      IdeToastTone.error => colors.error,
      IdeToastTone.success => colors.success,
    };
    return Semantics(
      container: true,
      explicitChildNodes: true,
      liveRegion: true,
      label: message,
      child: PanelCard(
        borderRadius: context.appRadii.allMedium,
        boxShadow: context.appEffects.overlayShadow(
          Theme.of(context).brightness,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            context.appSpacing.sm,
            context.appSpacing.xs,
            context.appSpacing.xxs,
            context.appSpacing.xs,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: context.appTypography.bodySmall.copyWith(
                    color: messageColor,
                  ),
                ),
              ),
              SizedBox(width: context.appSpacing.xxs),
              IdeIconButton(
                icon: Icons.close,
                semanticLabel: closeSemanticLabel,
                variant: IdeButtonVariant.ghost,
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
