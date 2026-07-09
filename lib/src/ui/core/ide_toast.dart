import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'ide_colors.dart';
import 'ide_effects.dart';
import 'ide_spacing.dart';
import 'ide_text_styles.dart';
import 'pane_widgets.dart';

/// IDE toast 语义色调。
enum IdeToastTone {
  /// 普通状态 / 信息提示。
  info,

  /// 错误或失败反馈。
  error,
}

/// 基于 `shadcn_flutter` 的统一 IDE toast 入口。
///
/// 视觉继续走 Graphite token（[PanelCard] / [IdeColors] / [IdeTextStyles]），
/// 展示与关闭则委托给 [sf.showToast]。
sf.ToastOverlay? showIdeToast(
  BuildContext context, {
  required String message,
  IdeToastTone tone = IdeToastTone.info,
  Duration showDuration = const Duration(seconds: 2),
  sf.ToastLocation location = sf.ToastLocation.bottomRight,
  bool dismissible = true,
}) {
  final trimmed = message.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  return sf.showToast(
    context: context,
    location: location,
    showDuration: showDuration,
    dismissible: dismissible,
    builder: (toastContext, overlay) {
      return _IdeToastCard(
        message: trimmed,
        tone: tone,
        onClose: overlay.close,
      );
    },
  );
}

class _IdeToastCard extends StatelessWidget {
  const _IdeToastCard({
    required this.message,
    required this.tone,
    required this.onClose,
  });

  final String message;
  final IdeToastTone tone;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final messageColor = switch (tone) {
      IdeToastTone.info => colors.textPrimary,
      IdeToastTone.error => colors.error,
    };

    return Semantics(
      liveRegion: true,
      label: message,
      child: PanelCard(
        borderRadius: IdeRadius.allMedium,
        boxShadow: IdeEffects.overlayShadow(sf.Theme.of(context).brightness),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            IdeSpacing.space12,
            IdeSpacing.space8,
            IdeSpacing.space4,
            IdeSpacing.space8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: textStyles.bodySmall.copyWith(color: messageColor),
                ),
              ),
              const SizedBox(width: IdeSpacing.space4),
              sf.IconButton.ghost(
                onPressed: onClose,
                size: sf.ButtonSize.small,
                density: sf.ButtonDensity.iconDense,
                icon: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
