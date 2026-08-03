import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_index_controller.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

WorkspaceNode _file(String path) => WorkspaceNode(
  path: path,
  name: path.split(RegExp(r'[\\/]')).last,
  type: WorkspaceNodeType.file,
);

/// 测试用：不接真实 Directory.watch，避免假路径触发 OS 错误。
Stream<FileSystemEvent> _silentWatch(String root) =>
    const Stream<FileSystemEvent>.empty();

WorkspaceFileIndexController _controller({
  required WorkspaceFileWalkRunner runWalk,
  WorkspaceDirectoryWatchFactory? watchDirectory,
  Duration reindexDebounce = const Duration(milliseconds: 20),
}) {
  final controller = WorkspaceFileIndexController(
    runWalk: runWalk,
    watchDirectory: watchDirectory ?? _silentWatch,
    reindexDebounce: reindexDebounce,
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  test('filesFor 就绪前为 null，就绪后返回语料', () async {
    final controller = _controller(
      runWalk: (root) async => <WorkspaceNode>[_file('$root/a.dart')],
    );

    expect(controller.filesFor('/repo'), isNull);
    expect(controller.isReady('/repo'), isFalse);

    await controller.index('/repo');

    expect(controller.isReady('/repo'), isTrue);
    final files = controller.filesFor('/repo');
    expect(files, hasLength(1));
    expect(files!.single.path, '/repo/a.dart');
  });

  test('同一 root 并发 index 单飞，只触发一次 walk', () async {
    var walkCount = 0;
    final controller = _controller(
      runWalk: (root) async {
        walkCount += 1;
        return <WorkspaceNode>[_file('$root/a.dart')];
      },
    );

    await Future.wait([controller.index('/repo'), controller.index('/repo')]);

    expect(walkCount, 1);
    expect(controller.isReady('/repo'), isTrue);
  });

  test('walk 期间 invalidate 使陈旧结果被丢弃，新一轮 index 正常提交', () async {
    final gate = Completer<void>();
    var walkCount = 0;
    final controller = _controller(
      runWalk: (root) async {
        walkCount += 1;
        await gate.future;
        return <WorkspaceNode>[_file('$root/a.dart')];
      },
    );

    final first = controller.index('/repo');
    controller.invalidate('/repo');
    gate.complete();
    await first;

    expect(controller.isReady('/repo'), isFalse);

    final second = controller.index('/repo');
    await second;

    expect(walkCount, 2);
    expect(controller.isReady('/repo'), isTrue);
  });

  test('walk 期间 invalidate 后并发 index 会重新发起 walk 并就绪', () async {
    final gate = Completer<void>();
    var walkCount = 0;
    final controller = _controller(
      runWalk: (root) async {
        walkCount += 1;
        await gate.future;
        return <WorkspaceNode>[_file('$root/a.dart')];
      },
    );

    // 模拟：大项目打开后索引中 → 清除工作区 → 立刻重新打开。
    final first = controller.index('/repo');
    controller.invalidate('/repo');
    final second = controller.index('/repo');
    gate.complete();
    await Future.wait([first, second]);

    expect(walkCount, 2);
    expect(controller.isReady('/repo'), isTrue);
    expect(controller.filesFor('/repo')!.single.path, '/repo/a.dart');
  });

  test('语料就绪与 invalidate 会通知监听者', () async {
    final controller = _controller(
      runWalk: (root) async => <WorkspaceNode>[_file('$root/a.dart')],
    );

    var ticks = 0;
    controller.addListener(() => ticks += 1);

    await controller.index('/repo');
    expect(ticks, 1);

    controller.invalidate('/repo');
    expect(ticks, 2);

    // 重复 invalidate 且无语料时不额外通知。
    controller.invalidate('/repo');
    expect(ticks, 2);
  });

  test('invalidate 丢弃已提交语料', () async {
    final controller = _controller(
      runWalk: (root) async => <WorkspaceNode>[_file('$root/a.dart')],
    );

    await controller.index('/repo');
    expect(controller.isReady('/repo'), isTrue);

    controller.invalidate('/repo');

    expect(controller.isReady('/repo'), isFalse);
    expect(controller.filesFor('/repo'), isNull);
  });

  test('walk 失败仅记日志，语料保持未就绪且不抛出', () async {
    final controller = _controller(
      runWalk: (root) async => throw StateError('boom'),
    );

    await controller.index('/repo');

    expect(controller.isReady('/repo'), isFalse);
    expect(controller.filesFor('/repo'), isNull);
  });

  test('不同 root 的语料互相隔离', () async {
    final controller = _controller(
      runWalk: (root) async => <WorkspaceNode>[_file('$root/a.dart')],
    );

    await controller.index('/repoA');

    expect(controller.isReady('/repoA'), isTrue);
    expect(controller.isReady('/repoB'), isFalse);

    await controller.index('/repoB');

    expect(controller.filesFor('/repoA'), hasLength(1));
    expect(controller.filesFor('/repoB'), hasLength(1));
  });

  test('dispose 后 index 不再触发 walk', () async {
    var walkCount = 0;
    final controller = WorkspaceFileIndexController(
      runWalk: (root) async {
        walkCount += 1;
        return <WorkspaceNode>[_file('$root/a.dart')];
      },
      watchDirectory: _silentWatch,
    );

    await controller.index('/repo');
    controller.dispose();

    await controller.index('/repoB');

    expect(walkCount, 1);
  });

  group('Directory.watch 驱动的重索引', () {
    test('create 事件防抖后触发重扫并更新语料', () async {
      final events = StreamController<FileSystemEvent>.broadcast();
      addTearDown(events.close);

      var walkCount = 0;
      final controller = _controller(
        runWalk: (root) async {
          walkCount += 1;
          if (walkCount == 1) {
            return <WorkspaceNode>[_file('$root/a.dart')];
          }
          return <WorkspaceNode>[_file('$root/a.dart'), _file('$root/b.dart')];
        },
        watchDirectory: (_) => events.stream,
        reindexDebounce: const Duration(milliseconds: 30),
      );

      var ticks = 0;
      controller.addListener(() => ticks += 1);

      await controller.index('/repo');
      expect(walkCount, 1);
      expect(controller.filesFor('/repo'), hasLength(1));
      expect(ticks, 1);

      events.add(FileSystemCreateEvent('/repo/b.dart', false));
      // 未到 debounce 前不应重扫。
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(walkCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(walkCount, 2);
      expect(controller.filesFor('/repo'), hasLength(2));
      expect(ticks, 2);
    });

    test('modify 事件不触发重扫', () async {
      final events = StreamController<FileSystemEvent>.broadcast();
      addTearDown(events.close);

      var walkCount = 0;
      final controller = _controller(
        runWalk: (root) async {
          walkCount += 1;
          return <WorkspaceNode>[_file('$root/a.dart')];
        },
        watchDirectory: (_) => events.stream,
        reindexDebounce: const Duration(milliseconds: 20),
      );

      await controller.index('/repo');
      expect(walkCount, 1);

      events.add(FileSystemModifyEvent('/repo/a.dart', false, false));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(walkCount, 1);
    });

    test('忽略目录下的事件不触发重扫', () async {
      final events = StreamController<FileSystemEvent>.broadcast();
      addTearDown(events.close);

      var walkCount = 0;
      final controller = _controller(
        runWalk: (root) async {
          walkCount += 1;
          return <WorkspaceNode>[_file('$root/a.dart')];
        },
        watchDirectory: (_) => events.stream,
        reindexDebounce: const Duration(milliseconds: 20),
      );

      await controller.index('/repo');
      expect(walkCount, 1);

      events.add(
        FileSystemCreateEvent('/repo/node_modules/pkg/index.js', false),
      );
      events.add(FileSystemDeleteEvent('/repo/build/app.so', false));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(walkCount, 1);
    });

    test('walk 期间收到 create 会在结束后补扫', () async {
      final events = StreamController<FileSystemEvent>.broadcast();
      addTearDown(events.close);
      final gate = Completer<void>();

      var walkCount = 0;
      final controller = _controller(
        runWalk: (root) async {
          walkCount += 1;
          if (walkCount == 1) {
            await gate.future;
            return <WorkspaceNode>[_file('$root/a.dart')];
          }
          return <WorkspaceNode>[_file('$root/a.dart'), _file('$root/b.dart')];
        },
        watchDirectory: (_) => events.stream,
        reindexDebounce: const Duration(milliseconds: 20),
      );

      final first = controller.index('/repo');
      // 在途 walk 中插入新文件事件。
      events.add(FileSystemCreateEvent('/repo/b.dart', false));
      gate.complete();
      await first;

      // 防抖补扫。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(walkCount, 2);
      expect(controller.filesFor('/repo'), hasLength(2));
    });

    test('路径未变的重扫不重复 notifyListeners', () async {
      final events = StreamController<FileSystemEvent>.broadcast();
      addTearDown(events.close);

      var walkCount = 0;
      final controller = _controller(
        runWalk: (root) async {
          walkCount += 1;
          return <WorkspaceNode>[_file('$root/a.dart')];
        },
        watchDirectory: (_) => events.stream,
        reindexDebounce: const Duration(milliseconds: 20),
      );

      var ticks = 0;
      controller.addListener(() => ticks += 1);

      await controller.index('/repo');
      expect(ticks, 1);

      events.add(FileSystemCreateEvent('/repo/tmp', true));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(walkCount, greaterThanOrEqualTo(2));
      expect(ticks, 1);
    });

    test('invalidate 停止监听，后续事件不再重扫', () async {
      final events = StreamController<FileSystemEvent>.broadcast();
      addTearDown(events.close);

      var walkCount = 0;
      final controller = _controller(
        runWalk: (root) async {
          walkCount += 1;
          return <WorkspaceNode>[_file('$root/a.dart')];
        },
        watchDirectory: (_) => events.stream,
        reindexDebounce: const Duration(milliseconds: 20),
      );

      await controller.index('/repo');
      expect(walkCount, 1);

      controller.invalidate('/repo');
      events.add(FileSystemCreateEvent('/repo/b.dart', false));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(walkCount, 1);
      expect(controller.isReady('/repo'), isFalse);
    });
  });
}
