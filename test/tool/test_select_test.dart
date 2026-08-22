import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_select.dart';

/// 选择器的失败模式只有一种值得怕：**漏选**。多选只是慢一点，漏选会让改坏的
/// 代码一路绿到 CI。所以下面的断言几乎全在钉"该选中的有没有选中"。
void main() {
  const packageLibDirectories = <String, String>{
    'zeta': 'lib',
    'zeta_agent_core': 'packages/zeta_agent_core/lib',
  };

  group('DartImportGraph.resolveDirectiveUri', () {
    String? resolve(String uri, String from) =>
        DartImportGraph.resolveDirectiveUri(uri, from, packageLibDirectories);

    test('把根 Package 的 package: URI 解析到 lib/', () {
      expect(
        resolve('package:zeta/src/a.dart', 'test/a_test.dart'),
        'lib/src/a.dart',
      );
    });

    test('把内部 Package 的 package: URI 解析到该 Package 的 lib/', () {
      expect(
        resolve('package:zeta_agent_core/zeta_agent_core.dart', 'lib/a.dart'),
        'packages/zeta_agent_core/lib/zeta_agent_core.dart',
      );
    });

    test('相对路径按来源文件所在目录解析，并归一化 ..', () {
      expect(
        resolve('../testing/harness.dart', 'test/src/features/a_test.dart'),
        'test/src/testing/harness.dart',
      );
      expect(
        resolve('./sibling.dart', 'test/src/a_test.dart'),
        'test/src/sibling.dart',
      );
    });

    test('dart: 与外部 package 不进图', () {
      expect(resolve('dart:io', 'lib/a.dart'), isNull);
      expect(resolve('package:flutter/material.dart', 'lib/a.dart'), isNull);
    });
  });

  group('DartImportGraph.dependentsClosure', () {
    test('沿"被谁 import"传递回溯', () {
      final graph = DartImportGraph.build(
        packageLibDirectories: packageLibDirectories,
        sources: <String, String>{
          'lib/src/leaf.dart': '',
          'lib/src/middle.dart': "import 'package:zeta/src/leaf.dart';",
          'test/src/top_test.dart': "import 'package:zeta/src/middle.dart';",
          'test/src/unrelated_test.dart': "import 'dart:io';",
        },
      );

      final closure = graph.dependentsClosure(<String>{'lib/src/leaf.dart'});

      expect(closure, contains('test/src/top_test.dart'));
      expect(closure, isNot(contains('test/src/unrelated_test.dart')));
    });

    test('barrel 的 export 也算依赖边', () {
      final graph = DartImportGraph.build(
        packageLibDirectories: packageLibDirectories,
        sources: <String, String>{
          'packages/zeta_agent_core/lib/src/model.dart': '',
          'packages/zeta_agent_core/lib/zeta_agent_core.dart':
              "export 'src/model.dart';",
          'test/src/uses_barrel_test.dart':
              "import 'package:zeta_agent_core/zeta_agent_core.dart';",
        },
      );

      expect(
        graph.dependentsClosure(<String>{
          'packages/zeta_agent_core/lib/src/model.dart',
        }),
        contains('test/src/uses_barrel_test.dart'),
      );
    });

    test('tool/ 下的 CLI 也进图：改它要重测 test/tool/ 里的对应测试', () {
      // 回归：早期只扫 lib/ 和 test/，于是改 tool/*.dart 一个测试都选不中，
      // 还会被"消失的 Dart 文件"规则误报成删除。
      final graph = DartImportGraph.build(
        packageLibDirectories: packageLibDirectories,
        sources: <String, String>{
          'tool/report_test_timings.dart': '',
          'test/tool/report_test_timings_test.dart':
              "import '../../tool/report_test_timings.dart';",
        },
      );

      expect(
        graph.dependentsClosure(<String>{'tool/report_test_timings.dart'}),
        contains('test/tool/report_test_timings_test.dart'),
      );
    });

    test('part 两半互为依赖：改 part 文件也要重测它的 library', () {
      final graph = DartImportGraph.build(
        packageLibDirectories: packageLibDirectories,
        sources: <String, String>{
          'lib/src/library.dart': "part 'library_part.dart';",
          'lib/src/library_part.dart': "part of 'library.dart';",
          'test/src/library_test.dart':
              "import 'package:zeta/src/library.dart';",
        },
      );

      expect(
        graph.dependentsClosure(<String>{'lib/src/library_part.dart'}),
        contains('test/src/library_test.dart'),
      );
    });
  });

  group('selectTests', () {
    final sources = <String, String>{
      'lib/src/features/agent/domain/model.dart': '',
      'lib/src/features/other/widget.dart': '',
      'test/src/features/agent/domain/model_test.dart':
          "import 'package:zeta/src/features/agent/domain/model.dart';",
      'test/src/features/other/widget_test.dart':
          "import 'package:zeta/src/features/other/widget.dart';",
      'test/src/architecture/feature_layering_guard_test.dart': '',
      'test/src/features/agent/architecture/purity_test.dart': '',
    };

    TestSelection select(List<String> changed, {bool includeGuards = true}) {
      return selectTests(
        changedPaths: changed,
        sources: sources,
        packageLibDirectories: packageLibDirectories,
        includeGuards: includeGuards,
      );
    }

    test('只选中反向依赖到的测试', () {
      final selection = select(<String>[
        'lib/src/features/other/widget.dart',
      ], includeGuards: false);

      expect(selection.rootTestPaths, <String>[
        'test/src/features/other/widget_test.dart',
      ]);
      expect(selection.isFullRun, isFalse);
    });

    test('有 Dart 改动就追加常驻架构守卫', () {
      final selection = select(<String>['lib/src/features/other/widget.dart']);

      expect(
        selection.rootTestPaths,
        contains('test/src/architecture/feature_layering_guard_test.dart'),
      );
    });

    test('改 Agent 代码时额外追加 Agent 架构守卫', () {
      final selection = select(<String>[
        'lib/src/features/agent/domain/model.dart',
      ]);

      expect(
        selection.rootTestPaths,
        containsAll(<String>[
          'test/src/features/agent/domain/model_test.dart',
          'test/src/features/agent/architecture/purity_test.dart',
        ]),
      );
    });

    test('改非 Agent 代码时不拉 Agent 守卫', () {
      final selection = select(<String>['lib/src/features/other/widget.dart']);

      expect(
        selection.rootTestPaths,
        isNot(
          contains('test/src/features/agent/architecture/purity_test.dart'),
        ),
      );
    });

    test('测试文件自身被改就一定跑，哪怕它谁也不 import', () {
      final selection = select(<String>[
        'test/src/architecture/feature_layering_guard_test.dart',
      ], includeGuards: false);

      expect(selection.rootTestPaths, <String>[
        'test/src/architecture/feature_layering_guard_test.dart',
      ]);
    });

    test('地基文件变更退化成全量', () {
      for (final trigger in <String>[
        'pubspec.yaml',
        'dart_test.yaml',
        '.github/workflows/ci.yml',
        'tool/test_shards.dart',
      ]) {
        final selection = select(<String>[trigger]);
        expect(selection.isFullRun, isTrue, reason: trigger);
        expect(selection.rootTestPaths, <String>['test'], reason: trigger);
      }
    });

    test('Dart 文件被删除或改名时退化成全量', () {
      // 文件已经不在 sources 里 = 磁盘上没有了；它的反向边随文件一起消失，
      // import 图圈不住影响面，只能跑全量。
      final selection = select(<String>['lib/src/features/gone/removed.dart']);

      expect(selection.isFullRun, isTrue);
      expect(selection.rootTestPaths, <String>['test']);
      expect(selection.reasons.join('\n'), contains('被删除或改名'));
    });

    test('被删除的测试文件同样触发全量', () {
      final selection = select(<String>[
        'test/src/features/gone/removed_test.dart',
      ]);

      expect(selection.isFullRun, isTrue);
    });

    test('纯文档改动不选任何测试', () {
      final selection = select(<String>['docs/architecture/overview.md']);

      expect(selection.rootTestPaths, isEmpty);
      expect(selection.runsPackageTests, isFalse);
    });

    test('命中内部 Package 测试时整体跑 packages/', () {
      final selection = selectTests(
        changedPaths: <String>['packages/zeta_agent_core/lib/src/model.dart'],
        includeGuards: false,
        packageLibDirectories: packageLibDirectories,
        sources: <String, String>{
          'packages/zeta_agent_core/lib/src/model.dart': '',
          'packages/zeta_agent_core/test/model_test.dart':
              "import 'package:zeta_agent_core/src/model.dart';",
        },
      );

      expect(selection.runsPackageTests, isTrue);
    });

    test('选中的测试能映射回分片 id', () {
      final selection = select(<String>[
        'lib/src/features/agent/domain/model.dart',
      ], includeGuards: false);

      // agent/domain 属于 6(agent-logic)。
      expect(selection.shardIds, <int>[6]);
    });
  });

  // 下面这条对着真实仓库跑：包名 → lib 目录的映射一旦漂移，反向闭包会静默变小。
  test('仓库里每一条内部 package: 导入都解析得到真实文件', () {
    final packageLibDirectories = <String, String>{'zeta': 'lib'};
    for (final entity in Directory('packages').listSync()) {
      if (entity is! Directory) {
        continue;
      }
      final name = _pubspecName(File('${entity.path}/pubspec.yaml'));
      if (name != null) {
        packageLibDirectories[name] = '${_relative(entity.path)}/lib';
      }
    }

    final directive = RegExp(
      r'''^\s*(?:import|export|part)\s+(?:of\s+)?(['"])([^'"]+)\1''',
      multiLine: true,
    );
    final unresolved = <String>[];
    var checked = 0;

    for (final root in <String>['lib', 'test', 'packages']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final from = _relative(entity.path);
        for (final match in directive.allMatches(entity.readAsStringSync())) {
          final uri = match.group(2)!;
          if (!uri.startsWith('package:')) {
            continue;
          }
          final packageName = uri.substring('package:'.length).split('/').first;
          if (!packageLibDirectories.containsKey(packageName)) {
            continue; // 外部依赖，不归我们管。
          }
          checked++;
          final resolved = DartImportGraph.resolveDirectiveUri(
            uri,
            from,
            packageLibDirectories,
          );
          if (resolved == null || !File(resolved).existsSync()) {
            unresolved.add('$from: $uri → ${resolved ?? '<null>'}');
          }
        }
      }
    }

    // 防空转：真的扫到了内部导入，才谈得上"没有解析失败"。
    expect(checked, greaterThan(500), reason: '内部 package: 导入扫得太少，断言多半失效了');
    expect(unresolved, isEmpty, reason: '这些内部导入解析不到文件，import 图会缺边');
  });
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
  return normalized.startsWith('$root/')
      ? normalized.substring(root.length + 1)
      : normalized;
}
