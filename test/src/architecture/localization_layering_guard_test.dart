import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 本地化分层守卫：generated l10n 只允许出现在 app/UI 适配层与 presentation。
///
/// application / data / domain 与 G1 共享层不得依赖 Flutter Locale、
/// BuildContext 或生成的 [AppLocalizations]。
void main() {
  final dartFiles = Directory('lib/src')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);

  test('generated l10n imports stay in app, UI and presentation adapters', () {
    final violations = <String>[];
    for (final file in dartFiles) {
      final path = _posix(file.path);
      if (_allowsGeneratedL10n(path)) {
        continue;
      }
      final source = file.readAsStringSync();
      if (_generatedL10nImport.hasMatch(source)) {
        violations.add(path);
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'generated/app_localizations 只能出现在 app、ui/localization、ui/core '
          '与 feature presentation。命中：\n${violations.join('\n')}',
    );
  });

  test(
    'application, data and domain do not use Locale, BuildContext or AppLocalizations',
    () {
      final violations = <String>[];
      for (final file in dartFiles) {
        final path = _posix(file.path);
        if (!_isContextFreeLayer(path)) {
          continue;
        }
        final code = _stripLineComments(file.readAsStringSync());
        for (final pattern in _forbiddenContextFreeIdentifiers) {
          if (pattern.hasMatch(code)) {
            violations.add('$path → ${pattern.pattern}');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'application/data/domain 不得引用 Flutter Locale、BuildContext 或 '
            'AppLocalizations。命中：\n${violations.join('\n')}',
      );
    },
  );

  test('G1 shared adapter files stay free of localization types', () {
    for (final path in _g1Files) {
      final code = _stripLineComments(File(path).readAsStringSync());
      expect(_generatedL10nImport.hasMatch(code), isFalse, reason: path);
      for (final pattern in _forbiddenContextFreeIdentifiers) {
        expect(
          pattern.hasMatch(code),
          isFalse,
          reason: '$path → ${pattern.pattern}',
        );
      }
    }
  });
}

const _g1Files = <String>[
  'packages/zeta_agent_core/lib/src/application/agent_event_pipeline.dart',
  'packages/zeta_agent_core/lib/src/application/agent_event_coalescing_policy.dart',
  'packages/zeta_agent_core/lib/src/application/coalescing_event_buffer.dart',
  'packages/zeta_agent_core/lib/src/application/bounded_event_dispatcher.dart',
  'packages/zeta_agent_core/lib/src/application/agent_conversation_timeline_store.dart',
];

final _generatedL10nImport = RegExp(
  r"package:zeta/src/ui/localization/(generated/app_localizations|app_localizations_x)\.dart",
);

final _forbiddenContextFreeIdentifiers = <RegExp>[
  RegExp(r'\bAppLocalizations\b'),
  RegExp(r'\bBuildContext\b'),
  RegExp(r'\bLocale\b'),
];

bool _allowsGeneratedL10n(String path) {
  if (path.startsWith('lib/src/app/')) {
    return true;
  }
  if (path.startsWith('lib/src/ui/')) {
    return true;
  }
  return path.contains('/presentation/');
}

bool _isContextFreeLayer(String path) {
  return path.contains('/application/') ||
      path.contains('/data/') ||
      path.contains('/domain/');
}

String _posix(String path) => path.replaceAll(r'\', '/');

String _stripLineComments(String source) {
  final out = StringBuffer();
  for (final line in source.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//') || trimmed.startsWith('///')) {
      continue;
    }
    final commentIndex = line.indexOf('//');
    if (commentIndex >= 0) {
      out.writeln(line.substring(0, commentIndex));
    } else {
      out.writeln(line);
    }
  }
  return out.toString();
}
