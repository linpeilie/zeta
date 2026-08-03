import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/workspace/domain/workspace_file_query.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

WorkspaceNode _file(String path) => WorkspaceNode(
  path: path,
  name: path.split(RegExp(r'[\\/]')).last,
  type: WorkspaceNodeType.file,
);

void main() {
  group('fuzzyRankWorkspaceFiles 空查询', () {
    test('按输入顺序返回前 limit 个', () {
      final files = [
        _file('/repo/a.dart'),
        _file('/repo/b.dart'),
        _file('/repo/c.dart'),
      ];
      final result = fuzzyRankWorkspaceFiles(files, query: '');
      expect(result.map((node) => node.name).toList(), <String>[
        'a.dart',
        'b.dart',
        'c.dart',
      ]);
    });

    test('limit 生效', () {
      final files = [
        for (var index = 0; index < 5; index++) _file('/repo/f$index.dart'),
      ];
      expect(fuzzyRankWorkspaceFiles(files, query: '', limit: 2), hasLength(2));
    });
  });

  group('fuzzyRankWorkspaceFiles 子序列匹配', () {
    test('"md" 匹配 main.dart', () {
      final files = [_file('/repo/other.txt'), _file('/repo/lib/main.dart')];
      final result = fuzzyRankWorkspaceFiles(files, query: 'md');
      expect(result.map((node) => node.name).toList(), <String>['main.dart']);
    });

    test('查询匹配路径而非名称时也能命中', () {
      final files = [_file('/repo/README.md'), _file('/repo/lib/main.dart')];
      final result = fuzzyRankWorkspaceFiles(files, query: 'lib');
      expect(result.map((node) => node.path).toList(), <String>[
        '/repo/lib/main.dart',
      ]);
    });

    test('缺任一子序列字符即淘汰', () {
      final files = [_file('/repo/main.dart')];
      expect(fuzzyRankWorkspaceFiles(files, query: 'xyz'), isEmpty);
    });

    test('目录节点不参与匹配', () {
      final files = [
        const WorkspaceNode(
          path: '/repo/src',
          name: 'src',
          type: WorkspaceNodeType.directory,
        ),
        _file('/repo/src.dart'),
      ];
      expect(fuzzyRankWorkspaceFiles(files, query: 'src'), hasLength(1));
    });
  });

  group('fuzzyRankWorkspaceFiles 评分排序', () {
    test('边界加分：前缀命中排在无边界弱命中前', () {
      final files = [_file('/repo/xmain.txt'), _file('/repo/main.dart')];
      final result = fuzzyRankWorkspaceFiles(files, query: 'main');
      expect(result.map((node) => node.name).toList(), <String>[
        'main.dart',
        'xmain.txt',
      ]);
    });

    test('同分时路径短优先', () {
      final files = [
        _file('/repo/deep/nested/dir/main.dart'),
        _file('/repo/main.dart'),
      ];
      final result = fuzzyRankWorkspaceFiles(files, query: 'main');
      expect(result.first.path, '/repo/main.dart');
    });

    test('同分同路径长时名称字母序优先', () {
      final files = [_file('/repo/ab.dart'), _file('/repo/aa.dart')];
      final result = fuzzyRankWorkspaceFiles(files, query: 'a');
      expect(result.first.name, 'aa.dart');
    });

    test('limit 对非空查询生效', () {
      final files = [
        for (var index = 0; index < 5; index++) _file('/repo/f$index.dart'),
      ];
      expect(
        fuzzyRankWorkspaceFiles(files, query: 'f', limit: 2),
        hasLength(2),
      );
    });
  });

  group('fuzzyRankWorkspaceFiles smart-case', () {
    test('全小写查询不区分大小写', () {
      final files = [_file('/repo/Main.Dart')];
      expect(fuzzyRankWorkspaceFiles(files, query: 'main'), hasLength(1));
    });

    test('含大写查询区分大小写', () {
      final files = [_file('/repo/Main.Dart')];
      expect(fuzzyRankWorkspaceFiles(files, query: 'Main'), hasLength(1));
      expect(fuzzyRankWorkspaceFiles(files, query: 'mainD'), isEmpty);
    });
  });
}
