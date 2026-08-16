// 扫描 lib/src 中用户可见的字符串字面量。
//
// 用途：建立本地化基线 allowlist，并禁止新增未登记的 Zeta 文案。
// 本工具只读，不改生产代码。
//
// 用法：
//   dart run tool/check_localized_ui_strings.dart --check
//   dart run tool/check_localized_ui_strings.dart --dump-allowlist
//   dart run tool/check_localized_ui_strings.dart --report

import 'dart:convert';
import 'dart:io';

const _allowlistPath = 'tool/localization_literal_allowlist.json';
const _scanRoot = 'lib/src';

const _brandLiterals = <String>{
  'Zeta',
  'Codex',
  'Grok',
  'Claude',
  'Claude Code',
  'ChatGPT',
  'OpenAI',
  'Anthropic',
  'xAI',
};

const _productTermLiterals = <String>{
  'Agent',
  'Agents',
  'Provider',
  'Thread',
  'Token',
  'Tokens',
  'MCP',
  'JSON-RPC',
  'ACP',
  'CLI',
};

final _cjkPattern = RegExp(r'[\u3400-\u9FFF]');
final _loggerCallPattern = RegExp(
  r'(?:loggerFor\s*\(|logger\s*\(|developer\.log\s*\(|'
  r'debugPrint\s*\(|'
  r'\.(?:info|warn|warning|debug|error|fine|severe|trace|wtf)\s*\()',
);
final _uiNamedArgPattern = RegExp(
  r'(?:title|subtitle|label|tooltip|message|description|hintText|'
  r'helperText|semanticLabel|semanticsLabel|placeholder|confirmLabel|'
  r'cancelLabel|actionLabel|emptyTitle|emptyMessage|errorTitle|'
  r'errorMessage|headerTitle|pageTitle|buttonLabel|statusText|'
  r'displayTitle|displayLabel|sectionTitle|dialogTitle)\s*:',
);
final _textWidgetPattern = RegExp(r'\b(?:Text|SelectableText|Tooltip)\s*\(');
final _protocolKeyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_\-./]*$');
final _pathLikePattern = RegExp(
  r'^(?:lib/|test/|package:|assets/|~|\./|/|[A-Za-z]:\\)',
);
final _generatedDirPattern = RegExp(r'/generated/');

void main(List<String> args) {
  if (args.length != 1 ||
      !const {'--check', '--dump-allowlist', '--report'}.contains(args.first)) {
    stderr.writeln(
      'Usage: dart run tool/check_localized_ui_strings.dart '
      '--check|--dump-allowlist|--report',
    );
    exitCode = 64;
    return;
  }

  final root = Directory(_scanRoot);
  if (!root.existsSync()) {
    stderr.writeln('scan root not found: $_scanRoot');
    exitCode = 66;
    return;
  }

  final hits = <_LiteralHit>[];
  for (final file in _dartFiles(root)) {
    hits.addAll(_scanFile(file));
  }
  hits.sort((a, b) {
    final byFile = a.file.compareTo(b.file);
    if (byFile != 0) {
      return byFile;
    }
    return a.line.compareTo(b.line);
  });

  switch (args.first) {
    case '--dump-allowlist':
      stdout.write(_encodeAllowlist(_allowlistEntriesFromHits(hits)));
      return;
    case '--report':
      _printReport(hits);
      return;
    case '--check':
      exitCode = _checkAgainstAllowlist(hits);
      return;
  }
}

List<File> _dartFiles(Directory root) {
  return root.listSync(recursive: true).whereType<File>().where((file) {
    final path = _normalize(file.path);
    return path.endsWith('.dart') && !_generatedDirPattern.hasMatch(path);
  }).toList()..sort((a, b) => _normalize(a.path).compareTo(_normalize(b.path)));
}

List<_LiteralHit> _scanFile(File file) {
  final source = file.readAsStringSync();
  final path = _normalize(file.path);
  final literals = _extractLiterals(source);
  final hits = <_LiteralHit>[];
  for (final literal in literals) {
    final classification = _classify(source, literal);
    if (classification == null) {
      continue;
    }
    hits.add(
      _LiteralHit(
        file: path,
        line: literal.line,
        column: literal.column,
        text: literal.text,
        field: literal.field,
        classification: classification,
      ),
    );
  }
  return hits;
}

/// 返回需要登记或报告的分类；日志/协议 key/纯品牌术语返回 null。
String? _classify(String source, _ExtractedLiteral literal) {
  final text = literal.text.trim();
  if (text.isEmpty) {
    return null;
  }
  if (_isLoggingContext(source, literal.offset)) {
    return null;
  }
  if (_brandLiterals.contains(text) || _productTermLiterals.contains(text)) {
    return null;
  }
  if (_pathLikePattern.hasMatch(text) || text.startsWith('http')) {
    return null;
  }
  if (!text.contains(' ') &&
      !_cjkPattern.hasMatch(text) &&
      _protocolKeyPattern.hasMatch(text)) {
    return null;
  }

  final hasCjk = _cjkPattern.hasMatch(text);
  final looksLikeSentence =
      text.contains(' ') && RegExp(r'[A-Za-z\u3400-\u9FFF]').hasMatch(text);
  final inUiSlot =
      _uiNamedArgPattern.hasMatch(literal.field) ||
      _textWidgetPattern.hasMatch(literal.field) ||
      literal.field.contains('semantics') ||
      literal.field.contains('tooltip');

  if (!hasCjk && !inUiSlot && !looksLikeSentence) {
    return null;
  }
  if (!hasCjk && !inUiSlot) {
    // 无 CJK、也不在 UI 槽位的英文句子更可能是异常/文档/协议说明，不当作用户可见文案。
    return null;
  }
  return 'zeta_copy';
}

bool _isLoggingContext(String source, int offset) {
  final start = offset > 240 ? offset - 240 : 0;
  final window = source.substring(start, offset);
  return _loggerCallPattern.hasMatch(window);
}

List<_AllowlistEntry> _allowlistEntriesFromHits(List<_LiteralHit> hits) {
  final seen = <String>{};
  final entries = <_AllowlistEntry>[];
  for (final hit in hits) {
    if (hit.classification != 'zeta_copy') {
      continue;
    }
    final key = '${hit.file}\u0000${hit.text}';
    if (!seen.add(key)) {
      continue;
    }
    entries.add(
      _AllowlistEntry(
        file: hit.file,
        text: hit.text,
        classification: hit.classification,
      ),
    );
  }
  return entries;
}

int _checkAgainstAllowlist(List<_LiteralHit> hits) {
  final allowlistFile = File(_allowlistPath);
  if (!allowlistFile.existsSync()) {
    stderr.writeln('allowlist not found: $_allowlistPath');
    return 66;
  }
  final decoded = jsonDecode(allowlistFile.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    stderr.writeln('allowlist must be a JSON object');
    return 65;
  }
  final rawEntries = decoded['entries'];
  if (rawEntries is! List) {
    stderr.writeln('allowlist.entries must be a list');
    return 65;
  }
  final allowed = <String>{};
  for (final entry in rawEntries) {
    if (entry is! Map) {
      continue;
    }
    final file = entry['file'];
    final text = entry['text'];
    if (file is String && text is String) {
      allowed.add('$file\u0000$text');
    }
  }

  final unexpected = <_LiteralHit>[];
  for (final hit in hits) {
    if (hit.classification != 'zeta_copy') {
      continue;
    }
    if (!allowed.contains('${hit.file}\u0000${hit.text}')) {
      unexpected.add(hit);
    }
  }

  if (unexpected.isEmpty) {
    stdout.writeln(
      'localization literal check passed '
      '(${hits.where((hit) => hit.classification == 'zeta_copy').length} '
      'existing zeta_copy hits, ${allowed.length} allowlist entries).',
    );
    return 0;
  }

  stderr.writeln('Unregistered user-visible literals (${unexpected.length}):');
  for (final hit in unexpected) {
    stderr.writeln(
      '${hit.file}:${hit.line}:${hit.column} '
      '[${hit.field}] ${jsonEncode(hit.text)}',
    );
  }
  return 1;
}

void _printReport(List<_LiteralHit> hits) {
  final visible = hits.where((hit) => hit.classification == 'zeta_copy');
  stdout.writeln('file\tline\tfield\tclassification\ttext');
  for (final hit in visible) {
    stdout.writeln(
      '${hit.file}\t${hit.line}\t${hit.field}\t'
      '${hit.classification}\t${jsonEncode(hit.text)}',
    );
  }
  stdout.writeln('# ${visible.length} user-visible zeta_copy literals');
}

String _encodeAllowlist(List<_AllowlistEntry> entries) {
  final payload = <String, Object>{
    'version': 1,
    'description':
        'Baseline user-visible Zeta copy. Existing debt is allowed; '
        'new (file, text) pairs must be registered or migrated to ARB.',
    'entries': [
      for (final entry in entries)
        <String, String>{
          'file': entry.file,
          'text': entry.text,
          'classification': entry.classification,
        },
    ],
  };
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(payload)}\n';
}

class _AllowlistEntry {
  const _AllowlistEntry({
    required this.file,
    required this.text,
    required this.classification,
  });

  final String file;
  final String text;
  final String classification;
}

class _LiteralHit {
  const _LiteralHit({
    required this.file,
    required this.line,
    required this.column,
    required this.text,
    required this.field,
    required this.classification,
  });

  final String file;
  final int line;
  final int column;
  final String text;
  final String field;
  final String classification;
}

class _ExtractedLiteral {
  const _ExtractedLiteral({
    required this.offset,
    required this.line,
    required this.column,
    required this.text,
    required this.field,
  });

  final int offset;
  final int line;
  final int column;
  final String text;
  final String field;
}

List<_ExtractedLiteral> _extractLiterals(String source) {
  final literals = <_ExtractedLiteral>[];
  final lineStarts = _lineStarts(source);
  var i = 0;
  var inBlockComment = false;

  while (i < source.length) {
    if (inBlockComment) {
      final end = source.indexOf('*/', i);
      if (end < 0) {
        break;
      }
      i = end + 2;
      inBlockComment = false;
      continue;
    }

    if (i + 1 < source.length && source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end + 1;
      continue;
    }
    if (i + 1 < source.length && source.startsWith('/*', i)) {
      inBlockComment = true;
      i += 2;
      continue;
    }

    final quote = _stringQuoteAt(source, i);
    if (quote != null) {
      if (_isImportUri(source, i)) {
        i = _skipString(source, i, quote);
        continue;
      }
      final extracted = _readStringLiteral(source, i, quote, lineStarts);
      if (extracted != null) {
        literals.add(extracted);
        i = extracted.offset + _rawLiteralLength(source, extracted.offset);
        continue;
      }
    }
    i += 1;
  }
  return literals;
}

_StringQuote? _stringQuoteAt(String source, int i) {
  var raw = false;
  var index = i;
  if (source[index] == 'r' && index + 1 < source.length) {
    raw = true;
    index += 1;
  }
  if (index + 2 < source.length && source.startsWith("'''", index)) {
    return _StringQuote(raw: raw, quote: "'''", start: i);
  }
  if (index + 2 < source.length && source.startsWith('"""', index)) {
    return _StringQuote(raw: raw, quote: '"""', start: i);
  }
  if (index < source.length && (source[index] == "'" || source[index] == '"')) {
    return _StringQuote(raw: raw, quote: source[index], start: i);
  }
  return null;
}

class _StringQuote {
  const _StringQuote({
    required this.raw,
    required this.quote,
    required this.start,
  });

  final bool raw;
  final String quote;
  final int start;
}

_ExtractedLiteral? _readStringLiteral(
  String source,
  int start,
  _StringQuote quote,
  List<int> lineStarts,
) {
  final bodyStart = start + (quote.raw ? 1 : 0) + quote.quote.length;
  var i = bodyStart;
  final buffer = StringBuffer();
  while (i < source.length) {
    if (source.startsWith(quote.quote, i)) {
      final line = _lineNumber(lineStarts, start);
      return _ExtractedLiteral(
        offset: start,
        line: line,
        column: start - lineStarts[line - 1] + 1,
        text: buffer.toString(),
        field: _nearestField(source, start),
      );
    }
    if (!quote.raw && source[i] == '\\') {
      if (i + 1 >= source.length) {
        return null;
      }
      buffer.write(source[i + 1]);
      i += 2;
      continue;
    }
    if (!quote.raw && source[i] == r'$' && i + 1 < source.length) {
      if (source[i + 1] == '{') {
        buffer.write(r'${}');
        i = _skipInterpolation(source, i + 2);
        continue;
      }
      buffer.write(r'${}');
      i += 1;
      while (i < source.length && _isIdentifierChar(source.codeUnitAt(i))) {
        i += 1;
      }
      continue;
    }
    buffer.write(source[i]);
    i += 1;
  }
  return null;
}

int _rawLiteralLength(String source, int start) {
  final quote = _stringQuoteAt(source, start);
  if (quote == null) {
    return 1;
  }
  var i = start + (quote.raw ? 1 : 0) + quote.quote.length;
  while (i < source.length) {
    if (source.startsWith(quote.quote, i)) {
      return i + quote.quote.length - start;
    }
    if (!quote.raw && source[i] == '\\' && i + 1 < source.length) {
      i += 2;
      continue;
    }
    i += 1;
  }
  return source.length - start;
}

int _skipString(String source, int start, _StringQuote quote) {
  return start + _rawLiteralLength(source, start);
}

int _skipInterpolation(String source, int start) {
  var depth = 1;
  var i = start;
  var inBlockComment = false;
  while (i < source.length && depth > 0) {
    if (inBlockComment) {
      final end = source.indexOf('*/', i);
      if (end < 0) {
        return source.length;
      }
      i = end + 2;
      inBlockComment = false;
      continue;
    }
    if (i + 1 < source.length && source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end + 1;
      continue;
    }
    if (i + 1 < source.length && source.startsWith('/*', i)) {
      inBlockComment = true;
      i += 2;
      continue;
    }
    final nested = _stringQuoteAt(source, i);
    if (nested != null) {
      i = _skipString(source, i, nested);
      continue;
    }
    if (source[i] == '{') {
      depth += 1;
    } else if (source[i] == '}') {
      depth -= 1;
    }
    i += 1;
  }
  return i;
}

bool _isImportUri(String source, int offset) {
  final before = source.substring(0, offset).trimRight();
  return before.endsWith('import') ||
      before.endsWith('export') ||
      before.endsWith('part');
}

String _nearestField(String source, int offset) {
  final start = offset > 180 ? offset - 180 : 0;
  final window = source.substring(start, offset);
  final named = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*:\s*$').firstMatch(window);
  if (named != null) {
    return '${named.group(1)}:';
  }
  final ctor = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*$').firstMatch(window);
  if (ctor != null) {
    return '${ctor.group(1)}(';
  }
  final assign = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*=\s*$').firstMatch(window);
  if (assign != null) {
    return assign.group(1)!;
  }
  return '(literal)';
}

bool _isIdentifierChar(int code) {
  return (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      (code >= 48 && code <= 57) ||
      code == 95;
}

List<int> _lineStarts(String source) {
  final starts = <int>[0];
  for (var i = 0; i < source.length; i++) {
    if (source[i] == '\n') {
      starts.add(i + 1);
    }
  }
  return starts;
}

int _lineNumber(List<int> lineStarts, int offset) {
  var low = 0;
  var high = lineStarts.length - 1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (lineStarts[mid] <= offset) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return high + 1;
}

String _normalize(String path) => path.replaceAll(r'\', '/');
