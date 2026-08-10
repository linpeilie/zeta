import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'ide_colors.dart';
import 'ide_dialog.dart';
import 'ide_effects.dart';
import 'ide_text_styles.dart';
import 'ide_toast.dart';
import 'pane_widgets.dart';

/// 打开本地图片预览弹层。
///
/// - 路径为空、文件不存在或不可读时：提示 toast 且不打开弹层，返回 `false`。
/// - 成功打开并关闭后返回 `true`。
///
/// 关闭方式：点遮罩、Esc、右上角关闭按钮。弹层内支持 [InteractiveViewer]
/// 缩放与平移。图片以内存字节渲染，避免部分环境下 [Image.file] 解码挂起。
Future<bool> showIdeLocalImagePreview(
  BuildContext context, {
  required String path,
  String? semanticsLabel,
}) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final file = File(trimmed);
  if (!file.existsSync()) {
    if (context.mounted) {
      showIdeToast(context, message: '图片文件不可用', tone: IdeToastTone.error);
    }
    return false;
  }

  // 同步读取：桌面本地缩略图体积可接受；并避免测试 fake_async 下异步 IO 挂起。
  late final Uint8List bytes;
  try {
    bytes = file.readAsBytesSync();
  } on FileSystemException {
    if (context.mounted) {
      showIdeToast(context, message: '图片文件不可用', tone: IdeToastTone.error);
    }
    return false;
  }
  if (bytes.isEmpty) {
    if (context.mounted) {
      showIdeToast(context, message: '图片文件不可用', tone: IdeToastTone.error);
    }
    return false;
  }

  final media = MediaQuery.sizeOf(context);
  final dialogWidth = (media.width * 0.92).clamp(280.0, 960.0);
  final dialogHeight = (media.height * 0.88).clamp(240.0, 720.0);
  final imageWidth = dialogWidth;
  final imageHeight = (dialogHeight - 96).clamp(160.0, 640.0);
  await showIdeDialog<void>(
    context: context,
    barrierDismissible: true,
    // 与 ide_effects 遮罩语义一致：深色半透明，避免裸 Color(0x…)。
    barrierColor: sf.Colors.black.withValues(alpha: 0.55),
    builder: (dialogContext) {
      return SizedBox(
        width: imageWidth,
        height: imageHeight,
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.memory(
            bytes,
            key: ValueKey<String>('ide-local-image-preview-file-$trimmed'),
            width: imageWidth,
            height: imageHeight,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) {
              return Center(
                child: Text(
                  '图片文件不可用',
                  style: IdeTextStyles.of(dialogContext).bodySmall,
                ),
              );
            },
          ),
        ),
      );
    },
  );
  return true;
}

/// 本地图片缩略图：成功时点击打开 [showIdeLocalImagePreview]；失败时不可点。
class IdeLocalImageThumbnail extends StatelessWidget {
  const IdeLocalImageThumbnail({
    super.key,
    required this.path,
    required this.size,
    this.borderRadius,
    this.enablePreview = true,
    this.tooltip = '查看大图',
    this.semanticLabel,
    this.imageKey,
  });

  /// 本地绝对路径。
  final String path;

  /// 缩略图边长。
  final double size;

  /// 圆角；默认 [IdeRadius.allSmall]。
  final BorderRadius? borderRadius;

  /// 是否允许点击预览（失败态强制关闭）。
  final bool enablePreview;

  /// 悬停提示。
  final String tooltip;

  /// 无障碍标签。
  final String? semanticLabel;

  /// 传给 [Image.file] 的 key（测试用）。
  final Key? imageKey;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final radius = borderRadius ?? IdeRadius.allSmall;
    final broken = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: radius,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            size: size >= 64 ? 20 : 18,
            color: colors.textTertiary,
          ),
        ),
      ),
    );

    final image = Image.file(
      File(path),
      key: imageKey,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => broken,
    );
    if (!enablePreview) {
      return ClipRRect(borderRadius: radius, child: image);
    }
    // 文件缺失时点击会 toast 且不打开弹层（见 [showIdeLocalImagePreview]）。
    return ClipRRect(
      borderRadius: radius,
      child: _PreviewTapTarget(
        path: path,
        tooltip: tooltip,
        semanticLabel: semanticLabel ?? '查看图片',
        child: image,
      ),
    );
  }
}

class _PreviewTapTarget extends StatelessWidget {
  const _PreviewTapTarget({
    required this.path,
    required this.tooltip,
    required this.semanticLabel,
    required this.child,
  });

  final String path;
  final String tooltip;
  final String semanticLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IdeTooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          label: semanticLabel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              unawaited(showIdeLocalImagePreview(context, path: path));
            },
            child: child,
          ),
        ),
      ),
    );
  }
}
