import 'package:app_ui/app_ui.dart';

/// A block skeleton placeholder for cards and charts.
class IdeSkeletonBlock extends StatelessWidget {
  /// Creates a skeleton block.
  const IdeSkeletonBlock({
    this.width,
    this.height = 80,
    this.borderRadius,
    super.key,
  });

  /// Optional block width.
  final double? width;

  /// Block height.
  final double height;

  /// Optional corner radius.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return IdeSkeletonBone(
      width: width,
      height: height,
      borderRadius: borderRadius ?? context.appRadii.allMedium,
    );
  }
}
