import 'dart:convert';

import 'package:glob/glob.dart';
import 'package:workspace_client/workspace_client.dart';

const Set<String> _ignoredEntryNames = <String>{
  '.dart_tool',
  '.git',
  '.idea',
  '.vscode',
  'build',
  'node_modules',
};

/// Creates the Repository-owned pure default/gitignore policy for [rootPath].
WorkspaceEntryFilter createWorkspaceEntryFilter(String rootPath) {
  final caseSensitive =
      WorkspacePathBoundary.contextFor(rootPath).style.name != 'windows';
  final cache = <GitignoreDocumentResponse, List<_GitignorePattern>>{};
  return (entry, documents) {
    if (_ignoredEntryNames.contains(entry.name)) {
      return entry.isDirectory
          ? WorkspaceEntryDisposition.prune
          : WorkspaceEntryDisposition.skip;
    }
    _GitignorePattern? lastMatch;
    var hasNegation = false;
    for (final document in documents) {
      final patterns = cache.putIfAbsent(
        document,
        () => _parseGitignore(document.contents, caseSensitive: caseSensitive),
      );
      final relativePath = _relativeTo(entry.path, document.basePath);
      if (relativePath == null) {
        continue;
      }
      for (final pattern in patterns) {
        hasNegation = hasNegation || pattern.isNegation;
        if (pattern.matches(relativePath, isDirectory: entry.isDirectory)) {
          lastMatch = pattern;
        }
      }
    }
    if (lastMatch == null || lastMatch.isNegation) {
      return WorkspaceEntryDisposition.include;
    }
    if (entry.isDirectory && !hasNegation) {
      return WorkspaceEntryDisposition.prune;
    }
    return WorkspaceEntryDisposition.skip;
  };
}

final class _GitignorePattern {
  const _GitignorePattern({
    required this.isNegation,
    required this.isDirectoryOnly,
    required this.anchored,
    required this.entryGlob,
    required this.descendantGlobs,
  });

  final bool isNegation;
  final bool isDirectoryOnly;
  final bool anchored;
  final Glob entryGlob;
  final List<Glob> descendantGlobs;

  bool matches(String relativePath, {required bool isDirectory}) {
    if ((!isDirectoryOnly || isDirectory) &&
        entryGlob.matches(anchored ? relativePath : _basename(relativePath))) {
      return true;
    }
    return descendantGlobs.any((glob) => glob.matches(relativePath));
  }
}

List<_GitignorePattern> _parseGitignore(
  String contents, {
  required bool caseSensitive,
}) {
  return List<_GitignorePattern>.unmodifiable(
    const LineSplitter()
        .convert(contents)
        .map((line) => _parseGitignoreLine(line, caseSensitive: caseSensitive))
        .nonNulls,
  );
}

_GitignorePattern? _parseGitignoreLine(
  String line, {
  required bool caseSensitive,
}) {
  var text = _stripTrailingSpaces(line);
  if (text.isEmpty || text.startsWith('#')) {
    return null;
  }
  var isNegation = false;
  if (text.startsWith('!')) {
    isNegation = true;
    text = text.substring(1);
  } else if (text.startsWith(r'\#')) {
    text = text.substring(1);
  }
  if (text.isEmpty) {
    return null;
  }
  var isDirectoryOnly = false;
  if (text.endsWith('/')) {
    isDirectoryOnly = true;
    text = text.substring(0, text.length - 1);
  }
  if (text.isEmpty) {
    return null;
  }
  var anchored = text.startsWith('/') || text.contains('/');
  if (text.startsWith('/')) {
    text = text.substring(1);
  } else if (text.startsWith('**/')) {
    anchored = false;
    text = text.substring(3);
  }
  if (text.isEmpty) {
    return null;
  }
  try {
    final descendants = anchored
        ? <Glob>[Glob('$text/**', caseSensitive: caseSensitive)]
        : <Glob>[
            Glob('**/$text', caseSensitive: caseSensitive),
            Glob('$text/**', caseSensitive: caseSensitive),
            Glob('**/$text/**', caseSensitive: caseSensitive),
          ];
    return _GitignorePattern(
      isNegation: isNegation,
      isDirectoryOnly: isDirectoryOnly,
      anchored: anchored,
      entryGlob: Glob(text, caseSensitive: caseSensitive),
      descendantGlobs: List<Glob>.unmodifiable(descendants),
    );
  } on FormatException {
    return null;
  }
}

String? _relativeTo(String path, String basePath) {
  final normalizedPath = path.replaceAll(r'\', '/');
  final normalizedBase = basePath.replaceAll(r'\', '/');
  final caseSensitive = !RegExp('^[A-Za-z]:/').hasMatch(normalizedBase);
  final comparedPath = caseSensitive
      ? normalizedPath
      : normalizedPath.toLowerCase();
  final comparedBase = caseSensitive
      ? normalizedBase
      : normalizedBase.toLowerCase();
  if (comparedPath == comparedBase) {
    return '';
  }
  if (!comparedPath.startsWith('$comparedBase/')) {
    return null;
  }
  return normalizedPath.substring(normalizedBase.length + 1);
}

String _basename(String path) {
  final index = path.lastIndexOf('/');
  return index < 0 ? path : path.substring(index + 1);
}

String _stripTrailingSpaces(String line) {
  var end = line.length;
  while (end > 0) {
    final character = line.codeUnitAt(end - 1);
    if (character != 0x20 && character != 0x09) {
      break;
    }
    if (end >= 2 && line.codeUnitAt(end - 2) == 0x5c) {
      break;
    }
    end -= 1;
  }
  return line.substring(0, end);
}
