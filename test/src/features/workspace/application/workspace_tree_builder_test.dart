import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/workspace/application/workspace_tree_builder.dart';

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

  test(
    'buildWorkspaceDirectoryChildren ignores configured folders and sorts entries',
    () {
      final root = Directory.systemTemp.createTempSync('zeta_workspace_');
      tempDirectories.add(root);

      Directory('${root.path}${Platform.pathSeparator}build').createSync();
      Directory('${root.path}${Platform.pathSeparator}.git').createSync();
      Directory('${root.path}${Platform.pathSeparator}lib').createSync();
      File(
        '${root.path}${Platform.pathSeparator}README.md',
      ).writeAsStringSync('docs');
      File(
        '${root.path}${Platform.pathSeparator}pubspec.yaml',
      ).writeAsStringSync('name: zeta');

      final children = buildWorkspaceDirectoryChildren(root);

      expect(children.map((node) => node.name).toList(), <String>[
        'lib',
        'pubspec.yaml',
        'README.md',
      ]);
      expect(children.first.isDirectory, isTrue);
      expect(
        children.any((node) => node.name == 'build' || node.name == '.git'),
        isFalse,
      );
    },
  );

  test(
    'buildWorkspaceDirectoryChildren restores expanded descendants lazily',
    () {
      final root = Directory.systemTemp.createTempSync('zeta_workspace_');
      tempDirectories.add(root);

      final libDirectory = Directory('${root.path}${Platform.pathSeparator}lib')
        ..createSync();
      File(
        '${libDirectory.path}${Platform.pathSeparator}main.dart',
      ).writeAsStringSync('void main() {}');

      final collapsedChildren = buildWorkspaceDirectoryChildren(root);
      final collapsedLib = collapsedChildren.singleWhere(
        (node) => node.name == 'lib',
      );
      expect(collapsedLib.childrenLoaded, isFalse);
      expect(collapsedLib.children, isEmpty);

      final expandedChildren = buildWorkspaceDirectoryChildren(
        root,
        expandedPaths: <String>{libDirectory.path},
      );
      final expandedLib = expandedChildren.singleWhere(
        (node) => node.name == 'lib',
      );
      expect(expandedLib.childrenLoaded, isTrue);
      expect(expandedLib.children.map((node) => node.name).toList(), <String>[
        'main.dart',
      ]);
    },
  );

  test(
    'buildWorkspaceDirectoryChildren returns empty for missing directories',
    () {
      final missingDirectory = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}zeta_missing_${DateTime.now().microsecondsSinceEpoch}',
      );

      expect(buildWorkspaceDirectoryChildren(missingDirectory), isEmpty);
    },
  );
}
