import 'package:flutter/widgets.dart';

/// 按离散约束档位缓存子树，避免 `LayoutBuilder` 在每个像素变化时重建业务树。
///
/// 仅在以下情况调用 [builder]：
/// - 首次布局；
/// - [selectBucket] 结果变化；
/// - 父级替换 [selectBucket] 或 [builder] 回调。
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
    // 稳定回调代表 builder 会从同一个 State 读取最新状态；父级仅因约束重建时
    // 继续复用 child。捕获了新配置的闭包身份会变化，仍按原语义失效缓存。
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
