/// 受影响测试选择器。
///
/// 开发循环里跑全量（2114 条 / 墙钟约 4m10s）是纯浪费：一次改动通常只碰得到
/// 几十条测试。这个 CLI 从 git 变更集出发，沿 import 图做**反向闭包**，算出
/// "哪些测试文件可能因为这次改动而改变行为"，只跑那些。
///
/// 安全边界：**宁可多选，不可漏选**。所有启发式都往"多跑几个"的方向兜底，
/// 并且全量仍然是 CI 的强制门禁——本地选择器漏了，合并前一定会被 CI 抓到。
///
/// 用法：
/// ```sh
/// dart run tool/test_select.dart                 # 选出受影响测试并直接跑
/// dart run tool/test_select.dart --print         # 只打印将要跑的路径
/// dart run tool/test_select.dart --shards        # 打印受影响的分片 id
/// dart run tool/test_select.dart --shard 3       # 跑指定分片
/// dart run tool/test_select.dart --base origin/dev
/// ```
library;

import 'dart:io';

import 'test_shards.dart';

/// 命中这些路径说明"地基"变了，import 图算不出影响面，直接跑全量。
const List<String> _fullRunTriggers = <String>[
  '.github/workflows/',
  'analysis_options.yaml',
  'dart_test.yaml',
  'pubspec.lock',
  'pubspec.yaml',
  'test/flutter_test_config.dart',
  'tool/test_select.dart',
  'tool/test_shards.dart',
];

/// 只要有 Dart 改动就跟着跑的架构守卫。
///
/// 这些守卫**扫全树**（读文件系统而不是 import 依赖），所以 import 图看不见它们
/// 与被改文件的关系——但它们恰恰是 G1–G8 里最容易被新代码违反的部分。约 13s，
/// 值这个钱。`--no-guards` 可关。
const List<String> _residentGuardPaths = <String>['test/src/architecture'];

/// 改动命中 Agent 相关代码时追加的守卫（共享层纯净性、payload 冻结等）。
const List<String> _agentGuardPaths = <String>[
  'test/src/features/agent/architecture',
];

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  if (options == null) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  if (options.help) {
    stdout.writeln(_usage);
    return;
  }

  final root = _repositoryRoot();
  Directory.current = root;

  // --shard N：不看变更集，直接跑清单里的那一片。
  if (options.shardId != null) {
    final shard = shardById(options.shardId!);
    if (shard == null) {
      stderr.writeln(
        '未知分片 ${options.shardId}；可用：'
        '${kRootTestShards.map((s) => '${s.id}(${s.name})').join(', ')}',
      );
      exitCode = 64;
      return;
    }
    if (options.printOnly) {
      stdout.writeln(shard.paths.join(' '));
      return;
    }
    exitCode = await _runFlutterTest(shard.paths, options.forwardedArguments);
    return;
  }

  final changed = options.changedOverride ?? _changedPaths(base: options.base);
  if (changed.isEmpty) {
    stdout.writeln('没有检测到变更，无受影响测试。');
    return;
  }

  final selection = selectTests(
    changedPaths: changed,
    sources: _readDartSources(),
    packageLibDirectories: _packageLibDirectories(),
    includeGuards: options.includeGuards,
  );

  _reportSelection(selection, changed);

  if (options.shardsOnly) {
    stdout.writeln(selection.shardIds.join(' '));
    return;
  }
  if (options.printOnly) {
    stdout.writeln(selection.rootTestPaths.join(' '));
    return;
  }
  if (selection.rootTestPaths.isEmpty && !selection.runsPackageTests) {
    stdout.writeln('无受影响测试，跳过。');
    return;
  }

  var failure = 0;
  if (selection.rootTestPaths.isNotEmpty) {
    failure = await _runFlutterTest(
      selection.rootTestPaths,
      options.forwardedArguments,
    );
  }
  if (selection.runsPackageTests) {
    final packagesExit = await _run('bash', <String>['tool/test_packages.sh']);
    if (failure == 0) {
      failure = packagesExit;
    }
  }
  exitCode = failure;
}

// ---------------------------------------------------------------------------
// 选择逻辑（纯函数，便于测试）
// ---------------------------------------------------------------------------

/// 一次选择的结果。
final class TestSelection {
  TestSelection({
    required this.rootTestPaths,
    required this.packageTestPaths,
    required this.isFullRun,
    required this.reasons,
    required this.totalRootTestCount,
  });

  /// 要传给根 `flutter test` 的路径（已排序去重）。
  final List<String> rootTestPaths;

  /// 命中的 `packages/*/test/**` 测试文件。
  final List<String> packageTestPaths;

  /// 是否退化成了全量。
  final bool isFullRun;

  /// 人类可读的触发理由，逐条打印给开发者看。
  final List<String> reasons;

  /// 仓库里根测试文件总数，用于算选中比例。
  final int totalRootTestCount;

  /// 内部 Package 有测试被命中——`tool/test_packages.sh` 没有文件级入口，
  /// 只要命中一个就整体跑（一共 8 个文件，很快）。
  bool get runsPackageTests => packageTestPaths.isNotEmpty;

  /// 选中的根测试落在哪些分片里，升序。
  List<int> get shardIds {
    final ids = <int>{};
    for (final path in rootTestPaths) {
      final shard = shardForTestPath(path);
      if (shard != null) {
        ids.add(shard.id);
      }
    }
    final sorted = ids.toList()..sort();
    return sorted;
  }
}

/// 从变更集算出要跑的测试。
///
/// [sources] 是仓库根相对路径 → 文件内容，覆盖 `lib/`、`test/`、
/// `packages/*/lib/`、`packages/*/test/`。
/// [packageLibDirectories] 是包名 → lib 目录（如 `zeta` → `lib`）。
TestSelection selectTests({
  required List<String> changedPaths,
  required Map<String, String> sources,
  required Map<String, String> packageLibDirectories,
  bool includeGuards = true,
}) {
  final allRootTests = sources.keys
      .where((path) => path.startsWith('test/') && path.endsWith('_test.dart'))
      .toList(growable: false);

  final reasons = <String>[];

  final trigger = changedPaths
      .where(
        (path) => _fullRunTriggers.any(
          (t) => t.endsWith('/') ? path.startsWith(t) : path == t,
        ),
      )
      .toList(growable: false);
  // 变更集里的 Dart 文件已经不在源码集合里 = 被删除或改名。它的依赖方无从查起
  // （反向边随文件一起没了），import 图给不出可信的影响面，只能退全量。
  final vanished = changedPaths
      .where((path) => path.endsWith('.dart') && !sources.containsKey(path))
      .toList(growable: false);
  if (vanished.isNotEmpty) {
    reasons.add('Dart 文件被删除或改名（${vanished.join(', ')}）→ 全量');
  }

  if (trigger.isNotEmpty) {
    reasons.add('地基文件变更（${trigger.join(', ')}）→ 全量');
  }
  if (trigger.isNotEmpty || vanished.isNotEmpty) {
    return TestSelection(
      rootTestPaths: <String>['test'],
      packageTestPaths: sources.keys
          .where((p) => _isPackageTest(p))
          .toList(growable: false),
      isFullRun: true,
      reasons: reasons,
      totalRootTestCount: allRootTests.length,
    );
  }

  final graph = DartImportGraph.build(
    sources: sources,
    packageLibDirectories: packageLibDirectories,
  );

  // 起点：变更的 Dart 文件本身。
  final seeds = <String>{
    ...changedPaths.where((path) => path.endsWith('.dart')),
  };

  final selected = <String>{};

  // 非 Dart 变更走单独的映射规则。
  for (final path in changedPaths.where((p) => !p.endsWith('.dart'))) {
    final mapped = _mapNonDartChange(path, sources, graph);
    if (mapped.isEmpty) {
      continue;
    }
    reasons.add('$path → ${mapped.length} 个测试');
    selected.addAll(mapped);
  }

  // 反向闭包：谁（传递地）依赖被改的文件，谁就得重跑。
  final reachable = graph.dependentsClosure(seeds);
  final fromGraph = reachable.where(_isTestFile).toSet();
  if (fromGraph.isNotEmpty) {
    reasons.add('import 反向闭包 → ${fromGraph.length} 个测试');
  }
  selected.addAll(fromGraph);

  // 变更文件本身就是测试的，直接算进来（它可能谁也不 import）。
  selected.addAll(seeds.where(_isTestFile));

  final touchesDart = seeds.isNotEmpty;
  if (includeGuards && touchesDart) {
    final guards = _expandGuardPaths(_residentGuardPaths, sources);
    selected.addAll(guards);
    reasons.add('常驻架构守卫 → ${guards.length} 个测试');

    final touchesAgent = changedPaths.any(
      (path) =>
          path.startsWith('lib/src/features/agent/') ||
          path.startsWith('packages/zeta_agent_'),
    );
    if (touchesAgent) {
      final agentGuards = _expandGuardPaths(_agentGuardPaths, sources);
      selected.addAll(agentGuards);
      reasons.add('Agent 架构守卫 → ${agentGuards.length} 个测试');
    }
  }

  final rootTests = selected.where((p) => p.startsWith('test/')).toList()
    ..sort();
  final packageTests = selected.where(_isPackageTest).toList()..sort();

  return TestSelection(
    rootTestPaths: rootTests,
    packageTestPaths: packageTests,
    isFullRun: false,
    reasons: reasons,
    totalRootTestCount: allRootTests.length,
  );
}

bool _isTestFile(String path) => path.endsWith('_test.dart');

bool _isPackageTest(String path) =>
    path.startsWith('packages/') &&
    path.contains('/test/') &&
    path.endsWith('_test.dart');

List<String> _expandGuardPaths(
  List<String> directories,
  Map<String, String> sources,
) {
  return sources.keys
      .where(
        (path) =>
            _isTestFile(path) &&
            directories.any((dir) => path.startsWith('$dir/')),
      )
      .toList(growable: false);
}

/// 非 Dart 变更 → 测试文件的映射。
///
/// 这里没有 import 图可用，只能靠约定：fixture 按文件名反查读取方，本地化资源
/// 打到本地化测试，`tool/` 脚本打到 `test/tool/`。查不到就退化到"所有会读
/// fixture 的测试"，而不是静默选空。
Set<String> _mapNonDartChange(
  String path,
  Map<String, String> sources,
  DartImportGraph graph,
) {
  if (path.endsWith('.arb') || path == 'l10n.yaml') {
    return sources.keys
        .where(
          (p) =>
              _isTestFile(p) &&
              (p.startsWith('test/src/ui/localization/') ||
                  p.startsWith('test/src/app/localization/')),
        )
        .toSet();
  }

  if (!path.startsWith('test/')) {
    return const <String>{};
  }

  final basename = path.split('/').last;
  final readers = sources.entries
      .where(
        (entry) => _isTestFile(entry.key) && entry.value.contains(basename),
      )
      .map((entry) => entry.key)
      .toSet();
  if (readers.isNotEmpty) {
    return readers;
  }

  // 兜底：fixture 名字没被字面量写死（拼接出来的），那就跑所有会读 fixture 的测试。
  return graph
      .dependentsClosure(<String>{'test/src/testing/fixture_reader.dart'})
      .where(_isTestFile)
      .toSet();
}

// ---------------------------------------------------------------------------
// import 图
// ---------------------------------------------------------------------------

/// Dart 文件之间的依赖图。
///
/// **刻意用行扫描而不是 analyzer AST。** 同目录的
/// `widget_test_hygiene_guard_test.dart` 论证过 AST 优于正则，那条守卫的失败
/// 模式是**漏判**（注释里的假 `agentProviderFactory` 能骗过正则）。这里方向反过来：
/// 被注释掉的 import 只会让反向闭包**多选**几个测试，多跑不会出错，而整图解析
/// 保持在百毫秒级——选择器每次改代码都要跑，慢一秒都是负担。
final class DartImportGraph {
  DartImportGraph._(this._dependents);

  /// 目标文件 → 依赖它的文件集合。
  final Map<String, Set<String>> _dependents;

  static final RegExp _directive = RegExp(
    r'''^\s*(?:import|export|part)\s+(?:of\s+)?(['"])([^'"]+)\1''',
    multiLine: true,
  );

  static DartImportGraph build({
    required Map<String, String> sources,
    required Map<String, String> packageLibDirectories,
  }) {
    final dependents = <String, Set<String>>{};
    void addEdge(String dependent, String dependency) {
      (dependents[dependency] ??= <String>{}).add(dependent);
    }

    for (final entry in sources.entries) {
      for (final match in _directive.allMatches(entry.value)) {
        final uri = match.group(2)!;
        final target = resolveDirectiveUri(
          uri,
          entry.key,
          packageLibDirectories,
        );
        if (target == null || !sources.containsKey(target)) {
          continue;
        }
        addEdge(entry.key, target);
        // `part` / `part of` 是同一个编译单元的两半，任一边变了另一边都要重测，
        // 所以补上反向边。
        if (match.group(0)!.trimLeft().startsWith('part')) {
          addEdge(target, entry.key);
        }
      }
    }
    return DartImportGraph._(dependents);
  }

  /// 把 import URI 解析成仓库根相对路径；解析不了返回 `null`。
  ///
  /// 公开是为了让 `test/tool/test_select_test.dart` 能对着真实仓库断言
  /// "每一条 `package:zeta*` 导入都解析得到存在的文件"——包名到 lib 目录的
  /// 映射一旦漂移，反向闭包会静默变小，那是最危险的失败模式。
  static String? resolveDirectiveUri(
    String uri,
    String fromPath,
    Map<String, String> packageLibDirectories,
  ) {
    if (uri.startsWith('dart:')) {
      return null;
    }
    if (uri.startsWith('package:')) {
      final rest = uri.substring('package:'.length);
      final slash = rest.indexOf('/');
      if (slash < 0) {
        return null;
      }
      final libDir = packageLibDirectories[rest.substring(0, slash)];
      if (libDir == null) {
        return null; // 外部依赖，不进图。
      }
      return '$libDir/${rest.substring(slash + 1)}';
    }
    if (uri.contains(':')) {
      return null;
    }
    final fromDir = fromPath.contains('/')
        ? fromPath.substring(0, fromPath.lastIndexOf('/'))
        : '';
    return _normalize(fromDir.isEmpty ? uri : '$fromDir/$uri');
  }

  static String _normalize(String path) {
    final parts = <String>[];
    for (final segment in path.split('/')) {
      if (segment == '.' || segment.isEmpty) {
        continue;
      }
      if (segment == '..') {
        if (parts.isNotEmpty) {
          parts.removeLast();
        }
        continue;
      }
      parts.add(segment);
    }
    return parts.join('/');
  }

  /// 从 [seeds] 出发，沿"被谁依赖"回溯出的传递闭包（含 seeds 本身）。
  Set<String> dependentsClosure(Set<String> seeds) {
    final visited = <String>{};
    final queue = <String>[...seeds];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (!visited.add(current)) {
        continue;
      }
      final callers = _dependents[current];
      if (callers != null) {
        queue.addAll(callers);
      }
    }
    return visited;
  }
}

// ---------------------------------------------------------------------------
// 文件系统 / git / 进程
// ---------------------------------------------------------------------------

Directory _repositoryRoot() {
  return Directory(Platform.script.resolve('..').toFilePath());
}

/// 扫描进图的目录。`packages/*/lib` 与 `packages/*/test` 在下面动态展开。
Map<String, String> _readDartSources() {
  final sources = <String, String>{};
  void scan(Directory directory) {
    if (!directory.existsSync()) {
      return;
    }
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final relative = _relative(entity.path);
      sources[relative] = entity.readAsStringSync();
    }
  }

  scan(Directory('lib'));
  scan(Directory('test'));
  // tool/ 也进图：`test/tool/*_test.dart` 用相对路径 import 这些 CLI
  //（例如 `import '../../tool/report_test_timings.dart';`），进图之后反向闭包
  // 天然覆盖它们，不需要给 tool/ 单独写一条映射规则。
  scan(Directory('tool'));
  for (final package in _packageDirectories()) {
    scan(Directory('$package/lib'));
    scan(Directory('$package/test'));
  }
  return sources;
}

List<String> _packageDirectories() {
  final root = Directory('packages');
  if (!root.existsSync()) {
    return const <String>[];
  }
  return root
      .listSync()
      .whereType<Directory>()
      .map((directory) => _relative(directory.path))
      .where((path) => File('$path/pubspec.yaml').existsSync())
      .toList(growable: false);
}

/// 包名 → lib 目录。根 Package 也在里面（`zeta` → `lib`）。
Map<String, String> _packageLibDirectories() {
  final mapping = <String, String>{};
  final rootName = _pubspecName(File('pubspec.yaml'));
  if (rootName != null) {
    mapping[rootName] = 'lib';
  }
  for (final package in _packageDirectories()) {
    final name = _pubspecName(File('$package/pubspec.yaml'));
    if (name != null) {
      mapping[name] = '$package/lib';
    }
  }
  return mapping;
}

String? _pubspecName(File pubspec) {
  if (!pubspec.existsSync()) {
    return null;
  }
  for (final line in pubspec.readAsLinesSync()) {
    final match = RegExp(r'^name:\s*(\S+)\s*$').firstMatch(line);
    if (match != null) {
      return match.group(1);
    }
  }
  return null;
}

String _relative(String path) {
  final normalized = path.replaceAll('\\', '/');
  final root = Directory.current.path.replaceAll('\\', '/');
  if (normalized.startsWith('$root/')) {
    return normalized.substring(root.length + 1);
  }
  return normalized;
}

/// 变更集：默认工作区（已跟踪的改动 + 未跟踪的新文件）；给了 [base] 就与它比。
List<String> _changedPaths({String? base}) {
  final paths = <String>{};
  void collect(List<String> arguments) {
    final result = Process.runSync('git', arguments);
    if (result.exitCode != 0) {
      return;
    }
    for (final line in (result.stdout as String).split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        paths.add(trimmed);
      }
    }
  }

  // 不加 --diff-filter：**删除和改名也要进变更集**。删掉一个文件同样会改变
  // 依赖方的行为，而它已经不在磁盘上，import 图圈不住影响面——下面的
  // "消失的 Dart 文件" 规则会把这种情况兜成全量。
  if (base != null) {
    collect(<String>['diff', '--name-only', '$base...HEAD']);
  }
  collect(<String>['diff', '--name-only', 'HEAD']);
  collect(<String>['ls-files', '--others', '--exclude-standard']);
  final sorted = paths.toList()..sort();
  return sorted;
}

void _reportSelection(TestSelection selection, List<String> changed) {
  stderr.writeln('变更 ${changed.length} 个文件：');
  for (final reason in selection.reasons) {
    stderr.writeln('  · $reason');
  }
  if (selection.isFullRun) {
    stderr.writeln('→ 跑全量。');
    return;
  }
  final total = selection.totalRootTestCount;
  final count = selection.rootTestPaths.length;
  stderr.writeln(
    '→ 选中 $count/$total 个根测试'
    '${selection.runsPackageTests ? ' + packages/ 全量' : ''}'
    '，分片 ${selection.shardIds.join(', ')}',
  );
  if (selection.runsPackageTests) {
    // --print 只输出根测试路径（它是拿去喂 `flutter test` 的），内部 Package 要
    // 另外一条命令跑。不点破的话，照着 --print 拼命令的人会漏掉这一半。
    stderr.writeln('  内部 Package 也被命中，还需跑：bash tool/test_packages.sh');
  }
  if (total > 0 && count / total > 0.6) {
    stderr.writeln('  提示：选中超过 60%，直接 `bash tool/test_full.sh` 可能更省事。');
  }
}

Future<int> _runFlutterTest(List<String> paths, List<String> forwarded) {
  return _run('flutter', <String>['test', ...paths, ...forwarded]);
}

Future<int> _run(String executable, List<String> arguments) async {
  stderr.writeln('\$ $executable ${arguments.join(' ')}');
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  return process.exitCode;
}

// ---------------------------------------------------------------------------
// CLI 选项
// ---------------------------------------------------------------------------

const String _usage = '''
用法: dart run tool/test_select.dart [选项] [-- 透传给 flutter test 的参数]

  --base <ref>   与 <ref> 比对而不是只看工作区
  --changed <a,b>  直接指定变更集（逗号分隔），用于验证选择器本身
  --shard <id>   跑指定分片（忽略变更集）
  --shards       只打印受影响的分片 id
  --print        只打印将要跑的根测试路径（喂给 flutter test），不执行；
                 内部 Package 是否命中看 stderr 的报告行
  --no-guards    不追加常驻架构守卫
  -h, --help     显示本帮助
''';

final class _Options {
  _Options({
    required this.base,
    required this.changedOverride,
    required this.shardId,
    required this.shardsOnly,
    required this.printOnly,
    required this.includeGuards,
    required this.help,
    required this.forwardedArguments,
  });

  final String? base;
  final List<String>? changedOverride;
  final int? shardId;
  final bool shardsOnly;
  final bool printOnly;
  final bool includeGuards;
  final bool help;
  final List<String> forwardedArguments;

  static _Options? parse(List<String> arguments) {
    String? base;
    List<String>? changedOverride;
    int? shardId;
    var shardsOnly = false;
    var printOnly = false;
    var includeGuards = true;
    var help = false;
    final forwarded = <String>[];

    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--') {
        forwarded.addAll(arguments.sublist(index + 1));
        break;
      }
      switch (argument) {
        case '--base':
          if (++index >= arguments.length) {
            return null;
          }
          base = arguments[index];
        case '--changed':
          if (++index >= arguments.length) {
            return null;
          }
          changedOverride = arguments[index]
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList();
        case '--shard':
          if (++index >= arguments.length) {
            return null;
          }
          shardId = int.tryParse(arguments[index]);
          if (shardId == null) {
            return null;
          }
        case '--shards':
          shardsOnly = true;
        case '--print':
          printOnly = true;
        case '--no-guards':
          includeGuards = false;
        case '-h':
        case '--help':
          help = true;
        default:
          if (argument.startsWith('-')) {
            return null;
          }
          forwarded.add(argument);
      }
    }

    return _Options(
      base: base,
      changedOverride: changedOverride,
      shardId: shardId,
      shardsOnly: shardsOnly,
      printOnly: printOnly,
      includeGuards: includeGuards,
      help: help,
      forwardedArguments: forwarded,
    );
  }
}
