import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_ui/zeta_ui.dart';

void main() {
  const epochA = IdeLayoutEpoch(
    crossAxisExtentInPhysicalPixels: 800,
    textScaleKey: 1.0,
    localeKey: 'zh',
    typographyEpoch: 1,
  );
  const epochB = IdeLayoutEpoch(
    crossAxisExtentInPhysicalPixels: 400,
    textScaleKey: 1.0,
    localeKey: 'zh',
    typographyEpoch: 1,
  );

  IdeVirtualItemDescriptor item(
    String id, {
    double estimated = 40,
    Object revision = 1,
    String kind = 'block',
  }) {
    return IdeVirtualItemDescriptor(
      id: id,
      kind: kind,
      layoutRevision: revision,
      estimatedExtent: estimated,
    );
  }

  group('19.1 IdeExtentIndex', () {
    test('1. 初始 estimates 的 total/prefix', () {
      final index = IdeExtentIndex()
        ..synchronize(<IdeVirtualItemDescriptor>[
          item('a', estimated: 10),
          item('b', estimated: 20),
          item('c', estimated: 30),
        ], epoch: epochA);

      expect(index.length, 3);
      expect(index.totalExtent, 60);
      expect(index.extentAt(0), 10);
      expect(index.extentAt(1), 20);
      expect(index.extentAt(2), 30);
      expect(index.offsetOf(0), 0);
      expect(index.offsetOf(1), 10);
      expect(index.offsetOf(2), 30);
      expect(index.endOf(2), 60);
    });

    test('2. point update 只改变该项及之后的 prefix', () {
      final index = IdeExtentIndex()
        ..synchronize(<IdeVirtualItemDescriptor>[
          item('a', estimated: 10),
          item('b', estimated: 20),
          item('c', estimated: 30),
          item('d', estimated: 40),
        ], epoch: epochA);

      final before = <double>[
        index.offsetOf(0),
        index.offsetOf(1),
        index.offsetOf(2),
        index.offsetOf(3),
      ];
      final totalBefore = index.totalExtent;

      final delta = index.updateMeasuredExtent(
        index: 1,
        measuredExtent: 50,
        epoch: epochA,
      );

      expect(delta.applied, isTrue);
      expect(delta.oldEffectiveExtent, 20);
      expect(delta.newEffectiveExtent, 50);
      expect(delta.delta, 30);
      expect(index.totalExtent, totalBefore + 30);

      // 目标项之前的 prefix 不变。
      expect(index.offsetOf(0), before[0]);
      expect(index.offsetOf(1), before[1]);
      // 该项及之后的 offset/end 平移 delta。
      expect(index.offsetOf(2), before[2] + 30);
      expect(index.offsetOf(3), before[3] + 30);
      expect(index.endOf(1), 10 + 50);
      expect(index.recordAt(1).isMeasurementFresh, isTrue);
      expect(index.recordAt(1).measuredExtent, 50);
    });

    test('2b. 亚像素 delta 不写入索引', () {
      final index = IdeExtentIndex()
        ..synchronize(<IdeVirtualItemDescriptor>[
          item('a', estimated: 40),
        ], epoch: epochA);

      final result = index.updateMeasuredExtent(
        index: 0,
        measuredExtent: 40.4,
        epoch: epochA,
      );

      expect(result.applied, isFalse);
      expect(index.totalExtent, 40);
      expect(index.extentAt(0), 40);
      expect(index.recordAt(0).measuredExtent, 40.4);
      expect(index.recordAt(0).isMeasurementFresh, isTrue);
    });

    test('3. indexAtOffset 边界', () {
      final index = IdeExtentIndex()
        ..synchronize(<IdeVirtualItemDescriptor>[
          item('a', estimated: 10),
          item('b', estimated: 20),
          item('c', estimated: 30),
        ], epoch: epochA);

      expect(index.indexAtOffset(-5), 0);
      expect(index.indexAtOffset(0), 0);
      expect(index.indexAtOffset(9.9), 0);
      expect(index.indexAtOffset(10), 1);
      expect(index.indexAtOffset(29.9), 1);
      expect(index.indexAtOffset(30), 2);
      expect(index.indexAtOffset(59.9), 2);
      expect(index.indexAtOffset(60), 2);
      expect(index.indexAtOffset(999), 2);

      final empty = IdeExtentIndex();
      expect(empty.indexAtOffset(0), kIdeExtentIndexEmptySentinel);
    });

    test('4. 连续 0 高度项', () {
      final index = IdeExtentIndex()
        ..synchronize(<IdeVirtualItemDescriptor>[
          item('z0', estimated: 0),
          item('z1', estimated: 0),
          item('body', estimated: 100),
          item('z2', estimated: 0),
          item('tail', estimated: 20),
        ], epoch: epochA);

      expect(index.totalExtent, 120);
      expect(index.indexAtOffset(0), 2);
      expect(index.indexAtOffset(50), 2);
      expect(index.indexAtOffset(100), 4);
      expect(index.offsetOf(2), 0);
      expect(index.offsetOf(4), 100);

      // 全 0 高度不会死循环。
      final zeros = IdeExtentIndex()
        ..synchronize(<IdeVirtualItemDescriptor>[
          item('a', estimated: 0),
          item('b', estimated: 0),
        ], epoch: epochA);
      expect(zeros.totalExtent, 0);
      expect(zeros.indexAtOffset(0), 1);
      expect(zeros.indexAtOffset(10), 1);
    });

    test('5. stable ID synchronize 复用测量', () {
      final index = IdeExtentIndex()
        ..synchronize(<IdeVirtualItemDescriptor>[
          item('a', estimated: 40),
          item('b', estimated: 40),
        ], epoch: epochA);
      index.updateMeasuredExtent(index: 0, measuredExtent: 120, epoch: epochA);

      index.synchronize(<IdeVirtualItemDescriptor>[
        item('a', estimated: 40),
        item('b', estimated: 40),
      ], epoch: epochA);

      expect(index.extentAt(0), 120);
      expect(index.recordAt(0).isMeasurementFresh, isTrue);
      expect(index.recordAt(0).measuredExtent, 120);
      expect(index.totalExtent, 160);
      expect(index.recordAt(0).id, 'a');
    });

    test('6. prepend 保留后续 ID 的测量并重建 offset', () {
      final index = IdeExtentIndex()
        ..synchronize(<IdeVirtualItemDescriptor>[
          item('a', estimated: 50),
          item('b', estimated: 60),
        ], epoch: epochA);
      index.updateMeasuredExtent(index: 0, measuredExtent: 80, epoch: epochA);
      index.updateMeasuredExtent(index: 1, measuredExtent: 90, epoch: epochA);

      index.synchronize(<IdeVirtualItemDescriptor>[
        item('pre', estimated: 25),
        item('a', estimated: 50),
        item('b', estimated: 60),
      ], epoch: epochA);

      expect(index.length, 3);
      expect(index.indexOfId('pre'), 0);
      expect(index.indexOfId('a'), 1);
      expect(index.indexOfId('b'), 2);
      expect(index.extentAt(0), 25);
      expect(index.extentAt(1), 80);
      expect(index.extentAt(2), 90);
      expect(index.offsetOf(1), 25);
      expect(index.offsetOf(2), 105);
      expect(index.totalExtent, 195);
      expect(index.recordAt(1).isMeasurementFresh, isTrue);
    });

    test('7. remove 后映射与总高度正确', () {
      final index = IdeExtentIndex()
        ..synchronize(<IdeVirtualItemDescriptor>[
          item('a', estimated: 10),
          item('b', estimated: 20),
          item('c', estimated: 30),
        ], epoch: epochA);
      index.updateMeasuredExtent(index: 1, measuredExtent: 50, epoch: epochA);

      index.synchronize(<IdeVirtualItemDescriptor>[
        item('a', estimated: 10),
        item('c', estimated: 30),
      ], epoch: epochA);

      expect(index.length, 2);
      expect(index.indexOfId('b'), isNull);
      expect(index.recordForId('b'), isNull);
      expect(index.totalExtent, 40);
      expect(index.indexOfId('c'), 1);
      expect(index.offsetOf(1), 10);
    });

    test('8. reorder 按新顺序重建 prefix 并复用测量', () {
      final index = IdeExtentIndex()
        ..synchronize(<IdeVirtualItemDescriptor>[
          item('a', estimated: 10),
          item('b', estimated: 20),
          item('c', estimated: 30),
        ], epoch: epochA);
      index.updateMeasuredExtent(index: 0, measuredExtent: 15, epoch: epochA);
      index.updateMeasuredExtent(index: 2, measuredExtent: 45, epoch: epochA);

      index.synchronize(<IdeVirtualItemDescriptor>[
        item('c', estimated: 30),
        item('a', estimated: 10),
        item('b', estimated: 20),
      ], epoch: epochA);

      expect(index.indexOfId('c'), 0);
      expect(index.indexOfId('a'), 1);
      expect(index.indexOfId('b'), 2);
      expect(index.extentAt(0), 45);
      expect(index.extentAt(1), 15);
      expect(index.extentAt(2), 20);
      expect(index.offsetOf(0), 0);
      expect(index.offsetOf(1), 45);
      expect(index.offsetOf(2), 60);
      expect(index.totalExtent, 80);
    });

    test('9. anchor ID 删除 fallback 所需的索引信息', () {
      final index = IdeExtentIndex()
        ..synchronize(<IdeVirtualItemDescriptor>[
          item('keep-0', estimated: 20),
          item('anchor', estimated: 40),
          item('keep-1', estimated: 30),
          item('keep-2', estimated: 50),
        ], epoch: epochA);

      const anchorId = 'anchor';
      final anchorOldIndex = index.indexOfId(anchorId)!;
      expect(anchorOldIndex, 1);
      final anchorOldOffset = index.offsetOf(anchorOldIndex);

      // 删除 anchor。
      index.synchronize(<IdeVirtualItemDescriptor>[
        item('keep-0', estimated: 20),
        item('keep-1', estimated: 30),
        item('keep-2', estimated: 50),
      ], epoch: epochA);

      expect(index.indexOfId(anchorId), isNull);

      // 规则：优先后方第一个仍存活项。
      String? fallbackId;
      for (var i = anchorOldIndex; i < 4; i++) {
        // 旧序列后方候选在新序列中查找。
      }
      const oldOrder = <String>['keep-0', 'anchor', 'keep-1', 'keep-2'];
      for (var i = anchorOldIndex + 1; i < oldOrder.length; i++) {
        if (index.indexOfId(oldOrder[i]) != null) {
          fallbackId = oldOrder[i];
          break;
        }
      }
      fallbackId ??= () {
        for (var i = anchorOldIndex - 1; i >= 0; i--) {
          if (index.indexOfId(oldOrder[i]) != null) {
            return oldOrder[i];
          }
        }
        return null;
      }();

      expect(fallbackId, 'keep-1');
      final fallbackIndex = index.indexOfId(fallbackId!)!;
      expect(fallbackIndex, 1);
      // 后方项继承了原 anchor 起点附近的内容坐标。
      expect(index.offsetOf(fallbackIndex), anchorOldOffset);
      expect(index.totalExtent, 100);
    });

    test('10. revision 变化将 measured 降级为 stale', () {
      final index = IdeExtentIndex()
        ..synchronize(<IdeVirtualItemDescriptor>[
          item('a', estimated: 40, revision: 1),
        ], epoch: epochA);
      index.updateMeasuredExtent(index: 0, measuredExtent: 120, epoch: epochA);

      index.synchronize(<IdeVirtualItemDescriptor>[
        item('a', estimated: 40, revision: 2),
      ], epoch: epochA);

      final record = index.recordAt(0);
      expect(record.measuredExtent, 120);
      expect(record.effectiveExtent, 120);
      expect(record.isMeasurementFresh, isFalse);
      expect(record.layoutRevision, 2);
      expect(index.totalExtent, 120);
    });

    test('11. epoch 变化保留旧值但标记 stale', () {
      final index = IdeExtentIndex()
        ..synchronize(<IdeVirtualItemDescriptor>[
          item('a', estimated: 40),
          item('b', estimated: 50),
        ], epoch: epochA);
      index.updateMeasuredExtent(index: 0, measuredExtent: 200, epoch: epochA);
      index.updateMeasuredExtent(index: 1, measuredExtent: 80, epoch: epochA);

      index.synchronize(<IdeVirtualItemDescriptor>[
        item('a', estimated: 40),
        item('b', estimated: 50),
      ], epoch: epochB);

      expect(index.extentAt(0), 200);
      expect(index.extentAt(1), 80);
      expect(index.totalExtent, 280);
      expect(index.recordAt(0).isMeasurementFresh, isFalse);
      expect(index.recordAt(1).isMeasurementFresh, isFalse);
      expect(index.recordAt(0).measuredExtent, 200);
      expect(index.epoch, epochB);

      // 重新测量后恢复 fresh。
      index.updateMeasuredExtent(index: 0, measuredExtent: 180, epoch: epochB);
      expect(index.recordAt(0).isMeasurementFresh, isTrue);
      expect(index.totalExtent, 260);
    });

    test('12. duplicate ID debug 契约', () {
      final index = IdeExtentIndex();
      expect(
        () => index.synchronize(<IdeVirtualItemDescriptor>[
          item('dup', estimated: 10),
          item('dup', estimated: 20),
        ], epoch: epochA),
        throwsA(isA<FlutterError>()),
      );
    });

    test('13. NaN/Infinity 与负 extent 的 debug 契约', () {
      final index = IdeExtentIndex()
        ..synchronize(<IdeVirtualItemDescriptor>[
          item('a', estimated: 40),
        ], epoch: epochA);

      expect(
        () => index.updateMeasuredExtent(
          index: 0,
          measuredExtent: double.nan,
          epoch: epochA,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => index.updateMeasuredExtent(
          index: 0,
          measuredExtent: double.infinity,
          epoch: epochA,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => index.updateMeasuredExtent(
          index: 0,
          measuredExtent: -8,
          epoch: epochA,
        ),
        throwsA(isA<AssertionError>()),
      );

      expect(
        () => IdeVirtualItemDescriptor(
          id: 'bad',
          kind: 'x',
          layoutRevision: 1,
          estimatedExtent: double.nan,
        ),
        throwsA(isA<AssertionError>()),
      );

      // 非有限 offset 不得污染索引状态。
      expect(index.indexAtOffset(double.nan), 0);
      expect(index.totalExtent, 40);
    });

    test('14. 固定种子 10,000 次随机 update 与朴素前缀和一致', () {
      const seed = 20260727;
      const itemCount = 128;
      const rounds = 10000;
      final random = math.Random(seed);

      final descriptors = List<IdeVirtualItemDescriptor>.generate(
        itemCount,
        (i) => item('id-$i', estimated: 20 + (i % 7) * 3),
      );
      final index = IdeExtentIndex()..synchronize(descriptors, epoch: epochA);
      final naive = _NaiveExtentArray([
        for (final d in descriptors) d.estimatedExtent,
      ]);

      for (var round = 0; round < rounds; round++) {
        final target = random.nextInt(itemCount);
        final measured = random.nextDouble() * 400;
        final delta = index.updateMeasuredExtent(
          index: target,
          measuredExtent: measured,
          epoch: epochA,
        );
        if (delta.applied) {
          naive.update(target, measured);
        }

        if (round % 250 == 0 || round == rounds - 1) {
          _expectIndexMatchesNaive(index, naive, tolerance: 1e-6);
        }
      }

      _expectIndexMatchesNaive(index, naive, tolerance: 1e-6);

      // 额外对照：随机 offset 查找。
      for (var i = 0; i < 200; i++) {
        final offset = random.nextDouble() * (naive.total + 10) - 5;
        expect(
          index.indexAtOffset(offset),
          naive.indexAtOffset(offset),
          reason: 'indexAtOffset mismatch at offset=$offset',
        );
      }
    });

    test('不得因新 estimate 批量改写已有未知项', () {
      final index = IdeExtentIndex()
        ..synchronize(<IdeVirtualItemDescriptor>[
          item('a', estimated: 40),
          item('b', estimated: 40),
          item('c', estimated: 40),
        ], epoch: epochA);
      // 仅测量 a；b/c 保持各自 estimate。
      index.updateMeasuredExtent(index: 0, measuredExtent: 200, epoch: epochA);

      // 同步时给出完全不同的 estimate，已存在未测项保持各自原 effective。
      index.synchronize(<IdeVirtualItemDescriptor>[
        item('a', estimated: 999),
        item('b', estimated: 999),
        item('c', estimated: 999),
      ], epoch: epochA);

      expect(index.extentAt(0), 200);
      // 从未测量：允许跟随 descriptor 新 estimate。
      expect(index.extentAt(1), 999);
      expect(index.extentAt(2), 999);

      // 再测 b 后，c 不得被“新平均值”改写。
      index.updateMeasuredExtent(index: 1, measuredExtent: 10, epoch: epochA);
      expect(index.extentAt(2), 999);
      expect(index.totalExtent, 200 + 10 + 999);
    });

    test('Fenwick 复杂度契约：前缀与 lower-bound 正确性抽样', () {
      final values = List<double>.generate(64, (i) => (i + 1).toDouble());
      final tree = IdeFenwickTree(values);
      var running = 0.0;
      for (var i = 0; i < values.length; i++) {
        running += values[i];
        expect(tree.prefixInclusive(i), closeTo(running, 1e-9));
        expect(tree.prefixExclusive(i), closeTo(running - values[i], 1e-9));
      }
      expect(tree.total, closeTo(running, 1e-9));

      tree.add(10, 5);
      expect(tree.prefixInclusive(10), closeTo(11.0 * 12.0 / 2 + 5, 1e-9));
      expect(tree.total, closeTo(running + 5, 1e-9));
    });
  });
}

void _expectIndexMatchesNaive(
  IdeExtentIndex index,
  _NaiveExtentArray naive, {
  required double tolerance,
}) {
  expect(index.length, naive.length);
  expect(index.totalExtent, closeTo(naive.total, tolerance));
  for (var i = 0; i < naive.length; i++) {
    expect(
      index.extentAt(i),
      closeTo(naive.extentAt(i), tolerance),
      reason: 'extentAt($i)',
    );
    expect(
      index.offsetOf(i),
      closeTo(naive.offsetOf(i), tolerance),
      reason: 'offsetOf($i)',
    );
  }
  // 覆盖头尾与中间多个采样点。
  final samples = <double>[
    -1,
    0,
    naive.total / 4,
    naive.total / 2,
    naive.total - 0.1,
    naive.total,
    naive.total + 50,
  ];
  for (final offset in samples) {
    expect(
      index.indexAtOffset(offset),
      naive.indexAtOffset(offset),
      reason: 'indexAtOffset($offset)',
    );
  }
}

/// 与 IdeExtentIndex 对照的朴素前缀和实现。
final class _NaiveExtentArray {
  _NaiveExtentArray(List<double> initial)
    : _extents = List<double>.from(initial);

  final List<double> _extents;

  int get length => _extents.length;

  double get total {
    var sum = 0.0;
    for (final value in _extents) {
      sum += value;
    }
    return sum;
  }

  double extentAt(int index) => _extents[index];

  double offsetOf(int index) {
    var sum = 0.0;
    for (var i = 0; i < index; i++) {
      sum += _extents[i];
    }
    return sum;
  }

  void update(int index, double value) {
    _extents[index] = value;
  }

  int indexAtOffset(double scrollOffset) {
    if (_extents.isEmpty) {
      return kIdeExtentIndexEmptySentinel;
    }
    if (!scrollOffset.isFinite) {
      scrollOffset = 0;
    }
    if (scrollOffset >= total) {
      return _extents.length - 1;
    }
    if (scrollOffset < 0) {
      scrollOffset = 0;
    }
    var end = 0.0;
    for (var i = 0; i < _extents.length; i++) {
      end += _extents[i];
      if (end > scrollOffset) {
        return i;
      }
    }
    return _extents.length - 1;
  }
}
