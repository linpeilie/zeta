import 'workspace_node.dart';

/// 对扁平工作区文件做模糊子序列排序，返回 top-k。
///
/// `query` 为空时保持输入顺序，仅取前 `limit` 个（对齐旧 `take(40)` 语义）。
/// 非空时对每个文件的 `name` 与 `path` 各做一次子序列评分，取较高者参与排序。
///
/// 评分启发式对齐 nucleo（grok-build 的 @ 完成底层）：
/// - smart-case：query 含大写字母则大小写敏感，否则不敏感；
/// - 子序列：query 各字符必须按序出现在文本中，缺任一字符即淘汰；
/// - 边界加分（起点 / 分隔符后 / camelCase 边界）+16、连续命中 +8、间隙每字符 -2；
/// - score <= 0 视为不匹配（noise 门限）。
List<WorkspaceNode> fuzzyRankWorkspaceFiles(
  Iterable<WorkspaceNode> files, {
  required String query,
  int limit = 40,
}) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return files.take(limit).toList(growable: false);
  }

  final caseSensitive = _hasUpperCase(trimmed);
  final scored = <({WorkspaceNode node, int score})>[];
  for (final file in files) {
    if (file.type != WorkspaceNodeType.file) {
      continue;
    }
    final nameScore = _fuzzyScore(file.name, trimmed, caseSensitive);
    final pathScore = _fuzzyScore(file.path, trimmed, caseSensitive);
    final score = nameScore > pathScore ? nameScore : pathScore;
    if (score > 0) {
      scored.add((node: file, score: score));
    }
  }

  scored.sort((a, b) {
    if (a.score != b.score) {
      return b.score.compareTo(a.score);
    }
    if (a.node.path.length != b.node.path.length) {
      return a.node.path.length.compareTo(b.node.path.length);
    }
    return a.node.name.toLowerCase().compareTo(b.node.name.toLowerCase());
  });
  return scored.take(limit).map((entry) => entry.node).toList(growable: false);
}

bool _hasUpperCase(String value) {
  for (final code in value.codeUnits) {
    if (_isUpper(code)) {
      return true;
    }
  }
  return false;
}

/// 对单个文本做子序列评分；未形成完整子序列时返回 0。
int _fuzzyScore(String original, String query, bool caseSensitive) {
  final haystack = caseSensitive ? original : original.toLowerCase();
  final needle = caseSensitive ? query : query.toLowerCase();

  var score = 0;
  var lastMatch = -1;
  var searchFrom = 0;
  for (var index = 0; index < needle.length; index++) {
    final code = needle.codeUnitAt(index);
    var found = -1;
    for (var pos = searchFrom; pos < haystack.length; pos++) {
      if (haystack.codeUnitAt(pos) == code) {
        found = pos;
        break;
      }
    }
    if (found < 0) {
      return 0;
    }
    if (_isWordBoundary(original, found)) {
      score += _boundaryBonus;
    }
    if (lastMatch >= 0 && found == lastMatch + 1) {
      score += _consecutiveBonus;
    } else if (lastMatch >= 0) {
      score -= _gapPenalty * (found - lastMatch - 1);
    }
    lastMatch = found;
    searchFrom = found + 1;
  }
  return score;
}

const int _boundaryBonus = 16;
const int _consecutiveBonus = 8;
const int _gapPenalty = 2;

/// 命中字符是否落在「词首」：文本起点、分隔符后，或 camelCase 边界（小写/数字转大写）。
///
/// 使用原始（大小写保留的）文本判定边界，这样不区分大小写匹配时 camelCase 边界仍然可见。
bool _isWordBoundary(String text, int index) {
  if (index == 0) {
    return true;
  }
  final previous = text.codeUnitAt(index - 1);
  if (_isSeparatorCodeUnit(previous)) {
    return true;
  }
  return _isLowerOrDigit(previous) && _isUpper(text.codeUnitAt(index));
}

bool _isSeparatorCodeUnit(int code) =>
    code == 0x2f || // /
    code == 0x5c || // \
    code == 0x2d || // -
    code == 0x5f || // _
    code == 0x2e; // .

bool _isUpper(int code) => code >= 0x41 && code <= 0x5a;

bool _isLower(int code) => code >= 0x61 && code <= 0x7a;

bool _isLowerOrDigit(int code) =>
    _isLower(code) || (code >= 0x30 && code <= 0x39);
