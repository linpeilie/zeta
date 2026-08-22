import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/test_shards.dart';

/// 分片覆盖守卫。
///
/// 根测试被 `tool/test_shards.dart` 切成若干片，CI 每片一个并行 Job。这种结构
/// 有一个安静的失败模式：**新增的测试文件不属于任何一片，于是永远不会被执行**，
/// 而 CI 全绿。AppFlowy 就踩了这个坑——它的 `integration_test/` 下有 15 个测试
/// 文件因为没被任何 runner import 而从来没跑过，包括整个 command palette 套件。
///
/// 这条守卫把那个洞焊死：`test/` 下每个 `*_test.dart` 必须**恰好**属于一片，
/// 不多不少。
void main() {
  final shardedTestFiles = <String, List<TestShard>>{};
  for (final file in _testFilesUnder('test')) {
    shardedTestFiles[file] = kRootTestShards
        .where((shard) => _covers(shard, file))
        .toList(growable: false);
  }

  test('test/ 下每个测试文件都属于某个分片', () {
    final orphans =
        shardedTestFiles.entries
            .where((entry) => entry.value.isEmpty)
            .map((entry) => entry.key)
            .toList()
          ..sort();

    // 防空转：真的扫到了测试文件，才谈得上"没有孤儿"。
    expect(
      shardedTestFiles,
      hasLength(greaterThan(200)),
      reason: '没扫到多少测试文件，守卫多半失效了',
    );
    expect(
      orphans,
      isEmpty,
      reason:
          '这些测试文件不属于任何分片，CI 永远不会跑到它们。'
          '把它们的目录加进 tool/test_shards.dart 的 kRootTestShards：\n'
          '${orphans.join('\n')}',
    );
  });

  test('没有测试文件同时落在两个分片里', () {
    final duplicated =
        shardedTestFiles.entries
            .where((entry) => entry.value.length > 1)
            .map(
              (entry) =>
                  '${entry.key} → ${entry.value.map((s) => s.name).join(', ')}',
            )
            .toList()
          ..sort();

    expect(
      duplicated,
      isEmpty,
      reason: '这些测试会被跑两遍，白烧 CI 时间：\n${duplicated.join('\n')}',
    );
  });

  test('分片清单里的路径都真实存在', () {
    final missing = <String>[];
    for (final shard in kRootTestShards) {
      for (final path in shard.paths) {
        if (!Directory(path).existsSync() && !File(path).existsSync()) {
          missing.add('${shard.id}(${shard.name}): $path');
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          '清单指向了不存在的路径——重构搬过目录之后忘了同步，'
          '对应分片会静默变空：\n${missing.join('\n')}',
    );
  });

  test('分片 id 连续且从 1 开始', () {
    final ids = kRootTestShards.map((shard) => shard.id).toList()..sort();

    expect(
      ids,
      List<int>.generate(kRootTestShards.length, (index) => index + 1),
      reason: 'CI 矩阵按 id 展开，id 断档会让某片没人跑',
    );
  });

  test('CI 矩阵的 shard 列表与分片清单一致', () {
    final workflow = File('.github/workflows/ci.yml');
    expect(
      workflow.existsSync(),
      isTrue,
      reason: '找不到 .github/workflows/ci.yml',
    );

    final match = RegExp(
      r'^\s*shard:\s*\[([^\]]*)\]\s*$',
      multiLine: true,
    ).firstMatch(workflow.readAsStringSync());
    expect(
      match,
      isNotNull,
      reason: 'ci.yml 里找不到 `shard: [...]` 矩阵；分片入口改名了就回来同步这条守卫',
    );

    final ciShardIds =
        match!
            .group(1)!
            .split(',')
            .map((value) => int.parse(value.trim()))
            .toList()
          ..sort();
    final manifestIds = kRootTestShards.map((shard) => shard.id).toList()
      ..sort();

    expect(
      ciShardIds,
      manifestIds,
      reason:
          '往 kRootTestShards 里加/删分片之后，'
          '要同步改 .github/workflows/ci.yml 的 `shard:` 矩阵',
    );
  });
}

List<String> _testFilesUnder(String directory) {
  return Directory(directory)
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.path.replaceAll('\\', '/'))
      .map(_relative)
      .where((path) => path.endsWith('_test.dart'))
      .toList(growable: false);
}

bool _covers(TestShard shard, String testPath) {
  return shard.paths.any(
    (path) => testPath == path || testPath.startsWith('$path/'),
  );
}

String _relative(String path) {
  final root = Directory.current.path.replaceAll('\\', '/');
  return path.startsWith('$root/') ? path.substring(root.length + 1) : path;
}
