import 'package:flutter/widgets.dart';

/// 按离散约束档位缓存子树，避免 `LayoutBuilder` 在每个像素变化时重建业务树。
///
/// 仅在以下情况调用 [builder]：
/// - 首次布局；
/// - [selectBucket] 结果变化；
/// - 父级重建导致本组件 [didUpdateWidget]（builder 可能已捕获新状态）。
///
/// 纯约束变化且 bucket 不变时返回**同一个 Widget 实例**，使 Flutter 跳过子树
/// Element 更新。主题、文字缩放等 InheritedWidget 仍通过既有依赖通知更新子树。
///
/// 不在 layout 回调中调用 `setState`。
class IdeConstraintBucketBuilder<T> extends StatefulWidget {
  const IdeConstraintBucketBuilder({
    required this.selectBucket,
    required this.builder,
    super.key,
  });

  /// 从当前约束映射到离散档位。应尽量只依赖会改变布局语义的维度。
  final T Function(BoxConstraints constraints) selectBucket;

  /// 在档位变化（或缓存失效）时构建业务子树。
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
    // 父级重建时 builder 闭包可能已捕获新状态；失效 child 缓存，
    // 下次 LayoutBuilder 回调会按当前 bucket 重新构建。
    _child = null;
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
