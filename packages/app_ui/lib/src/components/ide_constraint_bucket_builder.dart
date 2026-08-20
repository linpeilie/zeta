import 'package:flutter/widgets.dart';

/// Caches a subtree by a discrete layout-constraint bucket.
///
/// [builder] runs on the first layout, when [selectBucket] returns a different
/// value, or when either callback instance changes. Inherited dependencies
/// continue to update the retained subtree normally.
class IdeConstraintBucketBuilder<T> extends StatefulWidget {
  /// Creates a constraint-bucket builder.
  const IdeConstraintBucketBuilder({
    required this.selectBucket,
    required this.builder,
    super.key,
  });

  /// Maps the current constraints to a discrete layout bucket.
  final T Function(BoxConstraints constraints) selectBucket;

  /// Builds the subtree for the selected bucket.
  final Widget Function(BuildContext context, T bucket) builder;

  @override
  State<IdeConstraintBucketBuilder<T>> createState() =>
      _IdeConstraintBucketBuilderState<T>();
}

class _IdeConstraintBucketBuilderState<T>
    extends State<IdeConstraintBucketBuilder<T>> {
  T? _bucket;
  Widget? _child;
  bool _hasBucket = false;

  @override
  void didUpdateWidget(covariant IdeConstraintBucketBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectBucket != widget.selectBucket ||
        oldWidget.builder != widget.builder) {
      _child = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final nextBucket = widget.selectBucket(constraints);
        if (_hasBucket && _child != null && nextBucket == _bucket) {
          return _child!;
        }
        _bucket = nextBucket;
        _hasBucket = true;
        return _child = widget.builder(context, nextBucket);
      },
    );
  }
}
