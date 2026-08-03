import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/workspace/domain/workspace_gitignore.dart';

void main() {
  group('parseGitignoreLine', () {
    test('跳过空行与注释', () {
      expect(parseGitignoreLine('', caseSensitive: true), isNull);
      expect(parseGitignoreLine('   ', caseSensitive: true), isNull);
      expect(parseGitignoreLine('# comment', caseSensitive: true), isNull);
    });

    test('解析否定与目录专用', () {
      final negated = parseGitignoreLine('!keep.log', caseSensitive: true);
      expect(negated, isNotNull);
      expect(negated!.isNegation, isTrue);
      expect(negated.isDirOnly, isFalse);

      final dirOnly = parseGitignoreLine('build/', caseSensitive: true);
      expect(dirOnly!.isDirOnly, isTrue);
      expect(dirOnly.isNegation, isFalse);
    });

    test('锚定判断', () {
      expect(
        parseGitignoreLine('/build', caseSensitive: true)!.anchored,
        isTrue,
      );
      expect(
        parseGitignoreLine('foo/bar', caseSensitive: true)!.anchored,
        isTrue,
      );
      expect(
        parseGitignoreLine('*.log', caseSensitive: true)!.anchored,
        isFalse,
      );
      // 前导 `**/` 剥掉后按非锚定（任意深度，含根级）。
      expect(
        parseGitignoreLine('**/foo', caseSensitive: true)!.anchored,
        isFalse,
      );
    });

    test('畸形模式返回 null', () {
      expect(parseGitignoreLine('[unclosed', caseSensitive: true), isNull);
    });
  });

  group('GitignoreMatcher', () {
    GitignoreMatcher matcherFor(
      String root,
      String content, {
      bool caseSensitive = true,
    }) {
      final matcher = GitignoreMatcher(caseSensitive: caseSensitive);
      matcher.pushLayer(
        root,
        parseGitignore(content, caseSensitive: caseSensitive),
      );
      return matcher;
    }

    test('*.log 匹配任意深度 basename', () {
      final matcher = matcherFor('/repo', '*.log\n');
      expect(matcher.isIgnored('/repo/a.log', isDir: false), isTrue);
      expect(matcher.isIgnored('/repo/sub/b.log', isDir: false), isTrue);
      expect(matcher.isIgnored('/repo/a.txt', isDir: false), isFalse);
    });

    test('/build 锚定根目录，不匹配深层同名', () {
      final matcher = matcherFor('/repo', '/build\n');
      expect(matcher.isIgnored('/repo/build', isDir: true), isTrue);
      expect(matcher.isIgnored('/repo/build/x.txt', isDir: false), isTrue);
      expect(matcher.isIgnored('/repo/src/build', isDir: true), isFalse);
    });

    test('build/ 仅匹配目录条目', () {
      final matcher = matcherFor('/repo', 'build/\n');
      expect(matcher.isIgnored('/repo/build', isDir: true), isTrue);
      expect(matcher.isIgnored('/repo/build', isDir: false), isFalse);
    });

    test('否定模式重新包含', () {
      final matcher = matcherFor('/repo', '*.log\n!keep.log\n');
      expect(matcher.isIgnored('/repo/other.log', isDir: false), isTrue);
      expect(matcher.isIgnored('/repo/keep.log', isDir: false), isFalse);
    });

    test('同一文件内后行覆盖前行', () {
      final matcher = matcherFor('/repo', '*.log\n!keep.log\n*.log\n');
      // 最后一个 `*.log` 使 keep.log 重新被忽略。
      expect(matcher.isIgnored('/repo/keep.log', isDir: false), isTrue);
    });

    test('嵌套 .gitignore 深层覆盖浅层', () {
      final matcher = GitignoreMatcher(caseSensitive: true);
      matcher.pushLayer(
        '/repo',
        parseGitignore('*.tmp\n', caseSensitive: true),
      );
      matcher.pushLayer(
        '/repo/sub',
        parseGitignore('!keep.tmp\n', caseSensitive: true),
      );
      expect(matcher.isIgnored('/repo/sub/keep.tmp', isDir: false), isFalse);
      expect(matcher.isIgnored('/repo/sub/other.tmp', isDir: false), isTrue);
      expect(matcher.isIgnored('/repo/root.tmp', isDir: false), isTrue);
    });

    test('父目录命中覆盖子项', () {
      final matcher = matcherFor('/repo', 'logs\n');
      expect(matcher.isIgnored('/repo/logs', isDir: true), isTrue);
      expect(matcher.isIgnored('/repo/logs/x.txt', isDir: false), isTrue);
      expect(matcher.isIgnored('/repo/a/logs/x.txt', isDir: false), isTrue);
    });

    test('hasNegation 随 push/pop 变化', () {
      final matcher = GitignoreMatcher(caseSensitive: true);
      expect(matcher.hasNegation, isFalse);
      matcher.pushLayer(
        '/repo',
        parseGitignore('!keep.log\n', caseSensitive: true),
      );
      expect(matcher.hasNegation, isTrue);
      matcher.popLayer();
      expect(matcher.hasNegation, isFalse);
    });

    test('大小写参数生效', () {
      final insensitive = matcherFor('/repo', '*.log\n', caseSensitive: false);
      expect(insensitive.isIgnored('/repo/A.LOG', isDir: false), isTrue);

      final sensitive = matcherFor('/repo', '*.log\n', caseSensitive: true);
      expect(sensitive.isIgnored('/repo/A.LOG', isDir: false), isFalse);
    });

    test('popLayer 后规则失效', () {
      final matcher = matcherFor('/repo', '*.log\n');
      expect(matcher.isIgnored('/repo/a.log', isDir: false), isTrue);
      matcher.popLayer();
      expect(matcher.isIgnored('/repo/a.log', isDir: false), isFalse);
    });
  });
}
