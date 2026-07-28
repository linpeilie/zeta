import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_refresh_coordinator.dart';

void main() {
  group('AgentUsageRefreshCoordinator', () {
    test('合并尚未执行的重复刷新请求', () async {
      // Arrange
      var refreshCount = 0;
      final scheduledTasks = <Future<void> Function()>[];
      final coordinator = AgentUsageRefreshCoordinator(
        refresh: () async {
          refreshCount += 1;
        },
        schedule: scheduledTasks.add,
      );
      addTearDown(coordinator.dispose);

      // Act
      coordinator
        ..requestRefresh()
        ..requestRefresh();

      // Assert
      expect(scheduledTasks, hasLength(1));
      expect(refreshCount, 0);

      await scheduledTasks.removeAt(0)();

      expect(refreshCount, 1);
      expect(scheduledTasks, isEmpty);
    });

    test('执行期间的新请求会被丢弃', () async {
      // Arrange
      var refreshCount = 0;
      final firstRefreshGate = Completer<void>();
      final scheduledTasks = <Future<void> Function()>[];
      final coordinator = AgentUsageRefreshCoordinator(
        refresh: () async {
          refreshCount += 1;
          if (refreshCount == 1) {
            await firstRefreshGate.future;
          }
        },
        schedule: scheduledTasks.add,
      );
      addTearDown(coordinator.dispose);

      // Act
      coordinator.requestRefresh();
      final firstRun = scheduledTasks.removeAt(0)();
      await Future<void>.delayed(Duration.zero);
      coordinator
        ..requestRefresh()
        ..requestRefresh();

      // Assert
      expect(refreshCount, 1);
      expect(scheduledTasks, isEmpty);

      firstRefreshGate.complete();
      await firstRun;

      expect(scheduledTasks, isEmpty);

      coordinator.requestRefresh();

      expect(scheduledTasks, hasLength(1));
      await scheduledTasks.removeAt(0)();
      expect(refreshCount, 2);
    });

    test('释放后已提交的任务不再刷新', () async {
      // Arrange
      var refreshCount = 0;
      final scheduledTasks = <Future<void> Function()>[];
      final coordinator = AgentUsageRefreshCoordinator(
        refresh: () async {
          refreshCount += 1;
        },
        schedule: scheduledTasks.add,
      );
      coordinator.requestRefresh();
      final scheduledTask = scheduledTasks.single;

      // Act
      coordinator.dispose();
      await scheduledTask();
      coordinator.requestRefresh();

      // Assert
      expect(refreshCount, 0);
      expect(scheduledTasks, hasLength(1));
    });
  });
}
