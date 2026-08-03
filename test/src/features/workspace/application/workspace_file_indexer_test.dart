import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_indexer.dart';

void main() {
  final tempDirectories = <Directory>[];

  tearDown(() {
    for (final directory in tempDirectories) {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
    tempDirectories.clear();
  });

  Directory newTempDir([String suffix = '']) {
    final directory = Directory.systemTemp.createTempSync('zeta_index_$suffix');
    tempDirectories.add(directory);
    return directory;
  }

  String join(Directory dir, String name, [String? nested]) {
    final base = '${dir.path}${Platform.pathSeparator}$name';
    return nested == null ? base : '$base${Platform.pathSeparator}$nested';
  }

  test('buildWorkspaceFileCorpus 扁平化收集嵌套文件并跳过忽略目录', () {
    final root = newTempDir();
    final lib = Directory(join(root, 'lib'))..createSync();
    File(join(lib, 'main.dart')).writeAsStringSync('');
    File(join(root, 'README.md')).writeAsStringSync('');
    Directory(join(root, 'build')).createSync();
    File(join(root, 'build', 'out.js')).writeAsStringSync('');
    Directory(join(root, 'node_modules')).createSync();
    Directory(join(root, '.git')).createSync();

    final corpus = buildWorkspaceFileCorpus(root);

    final paths = corpus.map((node) => node.path).toSet();
    expect(paths, contains(join(lib, 'main.dart')));
    expect(paths, contains(join(root, 'README.md')));
    expect(corpus, hasLength(2));
    expect(corpus.every((node) => !node.isDirectory), isTrue);
    expect(
      corpus.every(
        (node) => node.name == node.path.split(RegExp(r'[\\/]')).last,
      ),
      isTrue,
    );
  });

  test('buildWorkspaceFileCorpus 缺失目录返回空', () {
    final root = newTempDir();
    final missing = Directory(join(root, 'does_not_exist'));
    final corpus = buildWorkspaceFileCorpus(missing);
    expect(corpus, isEmpty);
  });

  test('buildWorkspaceFileCorpus 达到 maxFiles 上限即停止', () {
    final root = newTempDir('cap_');
    for (var index = 0; index < 5; index++) {
      File(join(root, 'f$index.txt')).writeAsStringSync('');
    }
    final corpus = buildWorkspaceFileCorpus(root, maxFiles: 3);
    expect(corpus, hasLength(3));
  });

  test('buildWorkspaceFileCorpus 尊重 .gitignore（非 git 目录也生效）', () {
    final root = newTempDir();
    File(join(root, 'README.md')).writeAsStringSync('');
    File(join(root, 'debug.log')).writeAsStringSync('');
    final src = Directory(join(root, 'src'))..createSync();
    File(join(src, 'main.dart')).writeAsStringSync('');
    File(join(src, 'tmp.tmp')).writeAsStringSync('');
    Directory(join(root, 'build')).createSync();
    File(join(root, 'build', 'out.js')).writeAsStringSync('');
    File(join(root, '.gitignore')).writeAsStringSync('*.log\n/build/\n*.tmp\n');

    final corpus = buildWorkspaceFileCorpus(root, caseSensitive: true);
    final paths = corpus.map((node) => node.path).toSet();
    expect(paths, contains(join(root, 'README.md')));
    expect(paths, contains(join(src, 'main.dart')));
    expect(paths, isNot(contains(join(root, 'debug.log'))));
    expect(paths, isNot(contains(join(src, 'tmp.tmp'))));
    expect(paths, isNot(contains(join(root, 'build', 'out.js'))));
  });

  test('buildWorkspaceFileCorpus 否定模式重新包含文件', () {
    final root = newTempDir();
    File(join(root, 'keep.log')).writeAsStringSync('');
    File(join(root, 'drop.log')).writeAsStringSync('');
    File(join(root, '.gitignore')).writeAsStringSync('*.log\n!keep.log\n');

    final corpus = buildWorkspaceFileCorpus(root, caseSensitive: true);
    final paths = corpus.map((node) => node.path).toSet();
    expect(paths, contains(join(root, 'keep.log')));
    expect(paths, isNot(contains(join(root, 'drop.log'))));
  });

  test('buildWorkspaceFileCorpus 忽略目录内的否定可重新包含', () {
    final root = newTempDir();
    Directory(join(root, 'dist')).createSync();
    File(join(root, 'dist', 'keep.txt')).writeAsStringSync('');
    File(join(root, 'dist', 'drop.txt')).writeAsStringSync('');
    File(join(root, '.gitignore')).writeAsStringSync('dist/\n!dist/keep.txt\n');

    final corpus = buildWorkspaceFileCorpus(root, caseSensitive: true);
    final paths = corpus.map((node) => node.path).toSet();
    expect(paths, contains(join(root, 'dist', 'keep.txt')));
    expect(paths, isNot(contains(join(root, 'dist', 'drop.txt'))));
  });

  test('buildWorkspaceFileCorpus 嵌套 .gitignore 深层覆盖浅层', () {
    final root = newTempDir();
    final sub = Directory(join(root, 'sub'))..createSync();
    File(join(sub, 'keep.tmp')).writeAsStringSync('');
    File(join(sub, 'drop.tmp')).writeAsStringSync('');
    File(join(root, '.gitignore')).writeAsStringSync('*.tmp\n');
    File(join(sub, '.gitignore')).writeAsStringSync('!keep.tmp\n');

    final corpus = buildWorkspaceFileCorpus(root, caseSensitive: true);
    final paths = corpus.map((node) => node.path).toSet();
    expect(paths, contains(join(sub, 'keep.tmp')));
    expect(paths, isNot(contains(join(sub, 'drop.tmp'))));
  });

  test('buildWorkspaceFileCorpus 读取 .git/info/exclude', () {
    final root = newTempDir();
    final gitDir = Directory(join(root, '.git'))..createSync();
    Directory(join(gitDir, 'info')).createSync();
    File(join(gitDir, 'info', 'exclude')).writeAsStringSync('secret.tmp\n');
    File(join(root, 'open.txt')).writeAsStringSync('');
    File(join(root, 'secret.tmp')).writeAsStringSync('');

    final corpus = buildWorkspaceFileCorpus(root, caseSensitive: true);
    final paths = corpus.map((node) => node.path).toSet();
    expect(paths, contains(join(root, 'open.txt')));
    expect(paths, isNot(contains(join(root, 'secret.tmp'))));
  });

  test('buildWorkspaceFileCorpus 大小写按参数生效', () {
    final root = newTempDir();
    File(join(root, 'A.LOG')).writeAsStringSync('');
    File(join(root, '.gitignore')).writeAsStringSync('*.log\n');

    final insensitive = buildWorkspaceFileCorpus(root, caseSensitive: false);
    expect(insensitive.map((node) => node.name), isNot(contains('A.LOG')));

    final sensitive = buildWorkspaceFileCorpus(root, caseSensitive: true);
    expect(sensitive.map((node) => node.name), contains('A.LOG'));
  });
}
