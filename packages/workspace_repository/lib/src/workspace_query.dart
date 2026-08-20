import 'package:workspace_repository/src/workspace_models.dart';

/// Fuzzy-ranks indexed files by [query] and returns at most [limit] entries.
///
/// An empty query preserves the deterministic index order. Non-empty input
/// uses smart-case subsequence scoring over both file name and full path.
List<WorkspaceNode> fuzzyRankWorkspaceFiles(
  Iterable<WorkspaceNode> files, {
  required String query,
  int limit = 40,
}) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return List<WorkspaceNode>.unmodifiable(files.take(limit));
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

  scored.sort((first, second) {
    if (first.score != second.score) {
      return second.score.compareTo(first.score);
    }
    if (first.node.path.length != second.node.path.length) {
      return first.node.path.length.compareTo(second.node.path.length);
    }
    return first.node.name.toLowerCase().compareTo(
      second.node.name.toLowerCase(),
    );
  });
  return List<WorkspaceNode>.unmodifiable(
    scored.take(limit).map((entry) => entry.node),
  );
}

bool _hasUpperCase(String value) {
  for (final code in value.codeUnits) {
    if (_isUpper(code)) {
      return true;
    }
  }
  return false;
}

int _fuzzyScore(String original, String query, bool caseSensitive) {
  final haystack = caseSensitive ? original : original.toLowerCase();
  final needle = caseSensitive ? query : query.toLowerCase();
  var score = 0;
  var lastMatch = -1;
  var searchFrom = 0;
  for (var index = 0; index < needle.length; index++) {
    final code = needle.codeUnitAt(index);
    var found = -1;
    for (var position = searchFrom; position < haystack.length; position++) {
      if (haystack.codeUnitAt(position) == code) {
        found = position;
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

bool _isWordBoundary(String text, int index) {
  if (index == 0) {
    return true;
  }
  final previous = text.codeUnitAt(index - 1);
  if (_isSeparator(previous)) {
    return true;
  }
  return _isLowerOrDigit(previous) && _isUpper(text.codeUnitAt(index));
}

bool _isSeparator(int code) =>
    code == 0x2f ||
    code == 0x5c ||
    code == 0x2d ||
    code == 0x5f ||
    code == 0x2e;

bool _isUpper(int code) => code >= 0x41 && code <= 0x5a;

bool _isLower(int code) => code >= 0x61 && code <= 0x7a;

bool _isLowerOrDigit(int code) =>
    _isLower(code) || (code >= 0x30 && code <= 0x39);
