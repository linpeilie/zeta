import 'dart:io';

/// 遮挡可能出现在诊断文本中的凭证、认证头和本机用户目录。
///
/// 此函数只处理准备展示或记录的文本，不应把返回值用于协议请求或配置保存。
String redactSensitiveText(String value) {
  var result = value
      .replaceAll(
        RegExp(r'bearer\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false),
        'Bearer ••••••',
      )
      .replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]{12,}\b'), 'sk-••••••')
      .replaceAllMapped(
        RegExp(
          r'(api[_-]?key|token|secret|password|authorization|private[_-]?key)'
          r'(\s*[:=]\s*)'
          r'''("[^"]*"|'[^']*'|[^\s,;]+)''',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}${match.group(2)}••••••',
      );
  final home =
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  if (home != null && home.isNotEmpty) {
    result = result.replaceAll(home, '~');
  }
  return result;
}
