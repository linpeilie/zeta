import 'package:app_ui/app_ui.dart';

/// A single-line skeleton placeholder.
class IdeSkeletonLine extends StatelessWidget {
  /// Creates a skeleton line.
  const IdeSkeletonLine({
    this.width,
    this.height = 12,
    this.borderRadius,
    super.key,
  });

  /// Optional line width.
  final double? width;

  /// Line height.
  final double height;

  /// Optional corner radius.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return IdeSkeletonBone(
      width: width,
      height: height,
      borderRadius: borderRadius ?? context.appRadii.allSmall,
    );
  }
}
