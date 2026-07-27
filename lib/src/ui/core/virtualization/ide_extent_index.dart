/// 动态高度虚拟列表的高度前缀和索引。
///
/// 以稳定 item ID 保存每项 effective extent，通过 Fenwick Tree 在
/// `O(log n)` 内完成单点更新、前缀高度与 offset→index 查找。
/// 序列同步按 stable ID 复用测量；不得因 cohort 均值批量改写已有未知项。
library;

import 'package:flutter/foundation.dart';

import 'ide_virtual_item.dart';

/// 测量更新的亚像素阈值（logical pixel）。
///
/// 小于等于该绝对值的 delta 不会写入索引，避免布局噪声触发修正循环。
const double kIdeExtentMeasurementEpsilon = 0.5;

/// 空列表时 [IdeExtentIndex.indexAtOffset] 的约定 sentinel。
const int kIdeExtentIndexEmptySentinel = -1;

/// 基于 Fenwick Tree（Binary Indexed Tree）的 double 前缀和。
///
/// - 单点更新：`O(log n)`
/// - 前缀和：`O(log n)`
/// - 总高度：`O(1)`
/// - lower-bound（offset→index）：`O(log n)`
final class IdeFenwickTree {
  /// 以 [values] 作为初始叶子重建树。
  IdeFenwickTree(List<double> values) : _tree = <double>[0] {
    rebuild(values);
  }

  /// 创建空树。
  IdeFenwickTree.empty() : _tree = <double>[0], _length = 0, _total = 0;

  List<double> _tree;
  int _length = 0;
  double _total = 0;

  /// 叶子数量。
  int get length => _length;

  /// 全部叶子之和。
  double get total => _total;

  /// 以 [values] 全量重建，复杂度 `O(n)`。
  void rebuild(List<double> values) {
    _length = values.length;
    _tree = List<double>.filled(_length + 1, 0);
    _total = 0;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      _total += value;
      _addRaw(i, value);
    }
  }

  /// 将下标 [index]（0-based）的叶子增加 [delta]，`O(log n)`。
  void add(int index, double delta) {
    assert(index >= 0 && index < _length, 'Fenwick index out of range: $index');
    if (delta == 0) {
      return;
    }
    _total += delta;
    _addRaw(index, delta);
  }

  /// `sum(values[0 .. index])`，`index < 0` 时为 0，`O(log n)`。
  double prefixInclusive(int index) {
    if (index < 0 || _length == 0) {
      return 0;
    }
    final clamped = index >= _length ? _length - 1 : index;
    var sum = 0.0;
    for (var i = clamped + 1; i > 0; i -= i & -i) {
      sum += _tree[i];
    }
    return sum;
  }

  /// `sum(values[0 .. index-1])`，即 offsetOf(index)，`O(log n)`。
  double prefixExclusive(int index) {
    if (index <= 0) {
      return 0;
    }
    return prefixInclusive(index - 1);
  }

  /// 返回首个满足 `prefixInclusive(i) > offset` 的下标；若无则为 `_length`。
  ///
  /// 复杂度 `O(log n)`。调用方负责把越界结果夹到合法 item。
  int lowerBoundExclusiveEnd(double offset) {
    if (_length == 0) {
      return 0;
    }
    var idx = 0;
    var bitMask = _highestPowerOfTwo(_length);
    var sum = 0.0;
    while (bitMask != 0) {
      final next = idx + bitMask;
      if (next <= _length && sum + _tree[next] <= offset) {
        idx = next;
        sum += _tree[next];
      }
      bitMask >>= 1;
    }
    return idx;
  }

  void _addRaw(int index, double delta) {
    for (var i = index + 1; i <= _length; i += i & -i) {
      _tree[i] += delta;
    }
  }

  static int _highestPowerOfTwo(int n) {
    var value = 1;
    while ((value << 1) <= n) {
      value <<= 1;
    }
    return value;
  }
}

/// 按稳定 ID 维护动态高度的前缀和索引。
///
/// 职责边界：
/// - 只消费 [IdeVirtualItemDescriptor] 与测量值；
/// - 不依赖 Agent、Widget、BuildContext 或 Provider；
/// - 不因 cohort 或新平均值批量改写已有未知项。
final class IdeExtentIndex {
  /// 创建空索引。
  IdeExtentIndex()
    : _records = <IdeExtentRecord>[],
      _idToIndex = <String, int>{},
      _tree = IdeFenwickTree.empty();

  final List<IdeExtentRecord> _records;
  final Map<String, int> _idToIndex;
  final IdeFenwickTree _tree;

  IdeLayoutEpoch? _epoch;
  int _synchronizeGeneration = 0;

  /// 当前 item 数量。
  int get length => _records.length;

  /// 内容总高度（全部 effective extent 之和）。
  double get totalExtent => _tree.total;

  /// 最近一次 [synchronize] 使用的 layout epoch。
  IdeLayoutEpoch? get epoch => _epoch;

  /// 序列同步代数；每次 [synchronize] 递增，便于调试。
  int get synchronizeGeneration => _synchronizeGeneration;

  /// 按下标读取 record；越界抛出 [RangeError]。
  IdeExtentRecord recordAt(int index) => _records[index];

  /// 按稳定 ID 查找 record。
  IdeExtentRecord? recordForId(String id) {
    final index = _idToIndex[id];
    if (index == null) {
      return null;
    }
    return _records[index];
  }

  /// 按稳定 ID 查找下标。
  int? indexOfId(String id) => _idToIndex[id];

  /// 下标 [index] 的 effective extent。
  double extentAt(int index) {
    _checkIndex(index);
    return _records[index].effectiveExtent;
  }

  /// 下标 [index] 的内容起点 offset：`sum(extent[0 .. index-1])`。
  double offsetOf(int index) {
    _checkIndex(index);
    return _tree.prefixExclusive(index);
  }

  /// 下标 [index] 的内容终点：`offsetOf(index) + extentAt(index)`。
  double endOf(int index) {
    _checkIndex(index);
    return _tree.prefixInclusive(index);
  }

  /// 返回首个满足 `endOf(index) > scrollOffset` 的下标。
  ///
  /// 边界：
  /// - 空列表返回 [kIdeExtentIndexEmptySentinel]；
  /// - `scrollOffset <= 0` 返回首个 end 大于 offset 的项（跳过前导 0 高度项）；
  /// - `scrollOffset >= totalExtent` 返回最后一项；
  /// - 连续 0 高度项不会死循环。
  int indexAtOffset(double scrollOffset) {
    if (_records.isEmpty) {
      return kIdeExtentIndexEmptySentinel;
    }
    if (!scrollOffset.isFinite) {
      assert(() {
        debugPrint(
          'IdeExtentIndex.indexAtOffset 收到非有限 offset=$scrollOffset，'
          '将按 0 处理。',
        );
        return true;
      }());
      scrollOffset = 0;
    }
    if (scrollOffset >= totalExtent) {
      return _records.length - 1;
    }
    if (scrollOffset < 0) {
      scrollOffset = 0;
    }

    // lowerBound 返回首个 prefixInclusive(i) > offset 的 i。
    final candidate = _tree.lowerBoundExclusiveEnd(scrollOffset);
    if (candidate >= _records.length) {
      return _records.length - 1;
    }
    return candidate;
  }

  /// 按稳定 ID 同步序列，并一次性重建映射与 Fenwick Tree。
  ///
  /// 相同 ID 复用 measured/stale extent；revision 或 epoch 变化时将
  /// measurement 标为 stale，但保留旧值作为 estimate。新 ID 使用
  /// descriptor 的 [IdeVirtualItemDescriptor.estimatedExtent]。
  ///
  /// **duplicate ID**：debug 直接 assert；release 保留全部项对总高度的
  /// 贡献，但 `idToIndex` 只登记首次出现，避免把两项静默合并为一条
  /// record。
  void synchronize(
    List<IdeVirtualItemDescriptor> descriptors, {
    required IdeLayoutEpoch epoch,
  }) {
    _assertUniqueIds(descriptors);

    final previousById = <String, IdeExtentRecord>{
      for (final record in _records) record.id: record,
    };
    // 同一 ID 在旧序列重复时，Map 会留下最后一次；同步只复用一份 record。
    final reusedIds = <String>{};
    final nextRecords = List<IdeExtentRecord>.generate(descriptors.length, (
      index,
    ) {
      final descriptor = descriptors[index];
      final estimated = _sanitizeExtent(
        descriptor.estimatedExtent,
        context: 'descriptor ${descriptor.id}',
      );

      final previous = previousById[descriptor.id];
      if (previous == null || !reusedIds.add(descriptor.id)) {
        // 新 ID，或 release 模式下重复 ID 的后续项：使用 descriptor estimate。
        return IdeExtentRecord(
          id: descriptor.id,
          kind: descriptor.kind,
          layoutRevision: descriptor.layoutRevision,
          effectiveExtent: estimated,
        );
      }

      final revisionChanged =
          previous.layoutRevision != descriptor.layoutRevision;
      final epochChanged =
          previous.measuredEpoch != null && previous.measuredEpoch != epoch;
      final environmentChanged = _epoch != null && _epoch != epoch;

      previous.applyDescriptor(descriptor);

      if (previous.hasMeasuredExtent) {
        // 保留旧 measured 作为 effective；仅在仍匹配时保持 fresh。
        final stillFresh =
            previous.isMeasurementFresh &&
            !revisionChanged &&
            !epochChanged &&
            !environmentChanged &&
            previous.measuredEpoch == epoch;
        if (!stillFresh) {
          previous.markMeasurementStale();
        }
        // effective 保持旧 measured / 既有 effective，不回退到新 estimate。
      } else {
        // 从未测量：允许跟随最新 descriptor estimate。
        previous.setEffectiveExtent(estimated);
      }
      return previous;
    }, growable: false);

    _records
      ..clear()
      ..addAll(nextRecords);
    _idToIndex.clear();
    for (var i = 0; i < _records.length; i++) {
      // 首次出现优先，后续重复 ID 不覆盖。
      _idToIndex.putIfAbsent(_records[i].id, () => i);
    }
    _tree.rebuild([for (final record in _records) record.effectiveExtent]);
    _epoch = epoch;
    _synchronizeGeneration += 1;
  }

  /// 单点写入实测高度。
  ///
  /// `delta = measured - oldEffective`；仅当 `abs(delta) > 0.5` 时更新树。
  /// 总高度变化严格等于实际写入的 delta。非有限或负值在 debug assert，
  /// release 下安全 clamp 为 0。
  IdeExtentDelta updateMeasuredExtent({
    required int index,
    required double measuredExtent,
    required IdeLayoutEpoch epoch,
  }) {
    _checkIndex(index);
    final record = _records[index];
    final sanitized = _sanitizeExtent(
      measuredExtent,
      context: 'measured ${record.id}',
    );
    final oldEffective = record.effectiveExtent;
    final delta = sanitized - oldEffective;

    if (delta.abs() <= kIdeExtentMeasurementEpsilon) {
      // 亚像素噪声：不改树与 effective，只刷新实测快照。
      record.setMeasuredSnapshot(measuredExtent: sanitized, epoch: epoch);
      return IdeExtentDelta.none(
        index: index,
        id: record.id,
        effectiveExtent: oldEffective,
      );
    }

    record.setMeasured(measuredExtent: sanitized, epoch: epoch);
    _tree.add(index, delta);
    return IdeExtentDelta(
      index: index,
      id: record.id,
      oldEffectiveExtent: oldEffective,
      newEffectiveExtent: sanitized,
      delta: delta,
      applied: true,
    );
  }

  void _checkIndex(int index) {
    if (index < 0 || index >= _records.length) {
      throw RangeError.index(index, _records, 'index');
    }
  }

  void _assertUniqueIds(List<IdeVirtualItemDescriptor> descriptors) {
    assert(() {
      final seen = <String>{};
      for (final descriptor in descriptors) {
        if (!seen.add(descriptor.id)) {
          throw FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary('IdeExtentIndex 收到重复的 virtual item id。'),
            ErrorDescription('duplicate id: ${descriptor.id}'),
            ErrorHint('duplicate ID 属于 projection 契约错误，不能把两个 item 合并。'),
          ]);
        }
      }
      return true;
    }());
  }

  /// 将 extent 规范为有限且 `>= 0` 的值。
  ///
  /// debug：对 NaN/Infinity/负值 assert；release：clamp 到 0，避免污染 geometry。
  static double _sanitizeExtent(double value, {required String context}) {
    assert(
      value.isFinite && value >= 0,
      'IdeExtentIndex 非法 extent ($context): $value；release 将 clamp 为 0。',
    );
    if (!value.isFinite || value < 0) {
      return 0;
    }
    return value;
  }
}
