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
}
