/// 遮挡可能出现在诊断文本中的凭证、认证头和本机用户目录。
///
/// 此函数只处理准备展示或记录的文本，不应把返回值用于协议请求或配置保存。
/// 本模块保持纯 Dart：需要遮挡用户主目录的调用方必须显式传入
/// [homeDirectory]（由宿主侧解析，如 app 组合层或 feature data 层）。
String redactSensitiveText(String value, {String? homeDirectory}) {
  var result = value
      .replaceAllMapped(
        RegExp(
          r'\b((?:proxy-)?authorization)(\s*[:=]\s*)[^\r\n]*',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}${match.group(2)}••••••',
      )
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
  final home = homeDirectory;
  if (home != null && home.isNotEmpty) {
    result = result.replaceAll(home, '~');
  }
  return result;
}
