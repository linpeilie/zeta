/// 根测试套件的分片清单——**唯一事实源**。
///
/// `tool/test_select.dart`（跑分片 / 把受影响测试映射回分片）、
/// `tool/test_shard.{sh,ps1}`（本地与 CI 的分片入口）和
/// `test/src/architecture/test_shard_coverage_guard_test.dart`（覆盖守卫）
/// 都从这里读，改分片只改这一个文件。
///
/// **分片按语义分组，不按贪心装箱。** 开发者要能一眼判断自己的改动落在哪片；
/// 完美均衡的清单没人记得住，改一次目录就散架。当前最慢片是
/// `agent-presentation`（约 104s），它是目录粒度下的下界——`test/src/features/
/// agent/presentation` 一个目录就那么重，再加分片数也压不下去，除非拆到文件级。
///
/// 重平衡的输入是 `tool/report_test_timings.dart` 的输出（`test_shard.sh` 每片
/// 都会打印一份），不要凭感觉挪目录。
library;

/// 一个分片：CI 里的一个并行 Job，本地的一次 `flutter test <paths>`。
class TestShard {
  const TestShard({required this.id, required this.name, required this.paths});

  /// CI 矩阵里的编号，从 1 开始连续。守卫会比对 `ci.yml` 的 `shard:` 列表。
  final int id;

  /// 人类可读的名字，用于日志与 Job 名。
  final String name;

  /// 仓库根的相对路径（目录或文件），直接传给 `flutter test`。
  final List<String> paths;
}

/// 根 `test/` 目录的全部分片。
///
/// `packages/*/test/` **不在这里**：5 个内部 Package 一共只有 8 个测试文件，
/// 且需要各自的 `dart`/`flutter` 工具链与 `analyze`，继续走
/// `tool/test_packages.sh`，在 CI 里是独立的 `packages` Job。
const List<TestShard> kRootTestShards = <TestShard>[
  TestShard(
    id: 1,
    name: 'agent-presentation',
    paths: <String>['test/src/features/agent/presentation'],
  ),
  TestShard(id: 2, name: 'ui', paths: <String>['test/src/ui']),
  TestShard(
    id: 3,
    name: 'features',
    paths: <String>[
      'test/src/features/agent_management',
      'test/src/features/desktop_notifications',
      'test/src/features/ide_session',
      'test/src/features/project_threads',
      'test/src/features/settings',
      'test/src/features/usage_statistics',
      'test/src/features/workspace',
    ],
  ),
  TestShard(
    id: 4,
    name: 'app-shell',
    paths: <String>[
      'test/src/app',
      'test/src/architecture',
      'test/src/core',
      'test/src/testing',
      'test/tool',
    ],
  ),
  TestShard(
    id: 5,
    name: 'agent-data',
    paths: <String>['test/src/features/agent/data'],
  ),
  TestShard(
    id: 6,
    name: 'agent-logic',
    paths: <String>[
      'test/src/features/agent/application',
      'test/src/features/agent/architecture',
      'test/src/features/agent/domain',
    ],
  ),
];

/// 按 id 找分片；没有就返回 `null`。
TestShard? shardById(int id) {
  for (final shard in kRootTestShards) {
    if (shard.id == id) {
      return shard;
    }
  }
  return null;
}

/// 找出 [testPath]（仓库根相对、POSIX 分隔符）所属的分片。
///
/// 匹配方式是路径前缀：清单里写目录就覆盖整棵子树，写文件就只覆盖那个文件。
TestShard? shardForTestPath(String testPath) {
  for (final shard in kRootTestShards) {
    for (final path in shard.paths) {
      if (testPath == path || testPath.startsWith('$path/')) {
        return shard;
      }
    }
  }
  return null;
}
