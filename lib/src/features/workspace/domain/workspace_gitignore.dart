import 'dart:convert';

import 'package:glob/glob.dart';

/// 一条解析后的 gitignore 模式。
///
/// 匹配语义对齐 git：`!` 前缀否定、`/` 结尾仅匹配目录、含 `/`（或前导 `/`）锚定到所在
/// `.gitignore` 的目录、否则匹配任意深度的 basename。`*`/`?`/`[...]`/`**` 由
/// [package:glob](https://pub.dev/packages/glob) 负责。
final class GitignorePattern {
  const GitignorePattern._({
    required this.isNegation,
    required this.isDirOnly,
    required this.anchored,
    required this.entryGlob,
    required this.descendantGlobs,
  });

  /// 是否以 `!` 开头（白名单）。
  final bool isNegation;

  /// 是否以 `/` 结尾（仅匹配目录条目）。
  final bool isDirOnly;

  /// 是否锚定到所在 `.gitignore` 目录（模式含 `/` 或前导 `/`）。
  final bool anchored;

  /// 匹配条目本身的 glob。锚定时匹配完整相对路径；非锚定时匹配 basename（任意深度）。
  final Glob entryGlob;

  /// 匹配被忽略目录子项的 glob（`P/**`；非锚定再加 `**/P/**` 覆盖深层）。
  final List<Glob> descendantGlobs;

  /// 相对路径（`/` 分隔）是否命中该模式。
  bool matches(String relativePath, {required bool isDir}) {
    final checkEntry = !isDirOnly || isDir;
    if (checkEntry) {
      final candidate = anchored ? relativePath : _basename(relativePath);
      if (entryGlob.matches(candidate)) {
        return true;
      }
    }
    for (final glob in descendantGlobs) {
      if (glob.matches(relativePath)) {
        return true;
      }
    }
    return false;
  }
}

/// 解析单行 gitignore 模式；空行/注释/畸形（glob 编译失败）返回 null。
GitignorePattern? parseGitignoreLine(
  String line, {
  required bool caseSensitive,
}) {
  final trimmed = _stripTrailingSpaces(line);
  if (trimmed.isEmpty || trimmed.startsWith('#')) {
    return null;
  }
  var text = trimmed;
  var isNegation = false;
  if (text.startsWith('!')) {
    isNegation = true;
    text = text.substring(1);
  } else if (text.startsWith(r'\#')) {
    // `\#` 转义的字面量 #，不是注释。
    text = text.substring(1);
  }
  if (text.isEmpty) {
    return null;
  }
  var isDirOnly = false;
  if (text.endsWith('/')) {
    isDirOnly = true;
    text = text.substring(0, text.length - 1);
  }
  if (text.isEmpty) {
    return null;
  }
  // 前导 `**/` 使模式匹配任意深度（含根级）；glob 的 `**/` 前导不匹配零目录，需剥掉。
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
    if (anchored) {
      return GitignorePattern._(
        isNegation: isNegation,
        isDirOnly: isDirOnly,
        anchored: true,
        entryGlob: Glob(text, caseSensitive: caseSensitive),
        descendantGlobs: <Glob>[Glob('$text/**', caseSensitive: caseSensitive)],
      );
    }
    return GitignorePattern._(
      isNegation: isNegation,
      isDirOnly: isDirOnly,
      anchored: false,
      entryGlob: Glob(text, caseSensitive: caseSensitive),
      descendantGlobs: <Glob>[
        Glob('$text/**', caseSensitive: caseSensitive),
        Glob('**/$text/**', caseSensitive: caseSensitive),
      ],
    );
  } on FormatException {
    return null;
  }
}

/// 解析整份 `.gitignore` / `.git/info/exclude` 内容。
List<GitignorePattern> parseGitignore(
  String content, {
  required bool caseSensitive,
}) {
  final patterns = <GitignorePattern>[];
  for (final raw in const LineSplitter().convert(content)) {
    final pattern = parseGitignoreLine(raw, caseSensitive: caseSensitive);
    if (pattern != null) {
      patterns.add(pattern);
    }
  }
  return List<GitignorePattern>.unmodifiable(patterns);
}

/// 逐目录规则栈匹配器，last-match-wins。
///
/// 遍历时进入目录 push 该层 `.gitignore`（锚定基 = 该目录）、出目录 pop；顺序越靠后
/// 优先级越高（深目录覆盖浅目录、文件内后行覆盖前行）。`isIgnored` 返回最后一个命中
/// 模式是否非白名单。
final class GitignoreMatcher {
  GitignoreMatcher({required this.caseSensitive});

  final bool caseSensitive;

  final List<({String basePath, List<GitignorePattern> patterns})> _layers =
      <({String basePath, List<GitignorePattern> patterns})>[];
  bool _hasNegation = false;

  /// 是否存在任何否定（`!`）模式；存在时 walker 不能剪枝被忽略的目录，需下钻判定。
  bool get hasNegation => _hasNegation;

  void pushLayer(String basePath, List<GitignorePattern> patterns) {
    if (patterns.isEmpty) {
      return;
    }
    _layers.add((basePath: _normalize(basePath), patterns: patterns));
    if (patterns.any((pattern) => pattern.isNegation)) {
      _hasNegation = true;
    }
  }

  /// 移除最近一层；与 [pushLayer] 对称。
  void popLayer() {
    if (_layers.isEmpty) {
      return;
    }
    final removed = _layers.removeLast();
    if (removed.patterns.any((pattern) => pattern.isNegation)) {
      _hasNegation = _layers.any(
        (layer) => layer.patterns.any((pattern) => pattern.isNegation),
      );
    }
  }

  bool isIgnored(String absolutePath, {required bool isDir}) {
    final normalized = _normalize(absolutePath);
    GitignorePattern? lastMatch;
    for (final layer in _layers) {
      final relative = _relativeTo(normalized, layer.basePath);
      if (relative == null) {
        continue;
      }
      for (final pattern in layer.patterns) {
        if (pattern.matches(relative, isDir: isDir)) {
          lastMatch = pattern;
        }
      }
    }
    return lastMatch != null && !lastMatch.isNegation;
  }

  static String _normalize(String path) => path.replaceAll(r'\', '/');

  static String? _relativeTo(String path, String basePath) {
    if (path == basePath) {
      return '';
    }
    if (path.startsWith('$basePath/')) {
      return path.substring(basePath.length + 1);
    }
    return null;
  }
}

String _basename(String path) {
  final index = path.lastIndexOf('/');
  return index < 0 ? path : path.substring(index + 1);
}

String _stripTrailingSpaces(String line) {
  var end = line.length;
  while (end > 0) {
    final char = line.codeUnitAt(end - 1);
    if (char != 0x20 && char != 0x09) {
      break;
    }
    // 反斜杠转义的空白保留（`foo\ `）。
    if (end >= 2 && line.codeUnitAt(end - 2) == 0x5c) {
      break;
    }
    end -= 1;
  }
  return line.substring(0, end);
}
