import 'dart:io';

const _mask = '••••••';

/// Redacts credentials and local home paths from diagnostic [value].
///
/// The returned text is suitable only for diagnostics. It must never be used
/// for protocol requests or persisted configuration.
String redactSensitiveText(
  String value, {
  String? userHome,
  Map<String, String>? environment,
  bool? isWindows,
}) {
  var result = value
      .replaceAllMapped(
        RegExp(
          r'\b((?:proxy-)?authorization)(\s*[:=]\s*)[^\r\n]*',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}${match.group(2)}$_mask',
      )
      .replaceAll(
        RegExp(r'bearer\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false),
        'Bearer $_mask',
      )
      .replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]{12,}\b'), 'sk-$_mask')
      .replaceAllMapped(
        RegExp(
          '(api[_-]?key|token|secret|password|authorization|private[_-]?key)'
          r'(\s*[:=]\s*)'
          r'''("[^"]*"|'[^']*'|[^\s,;]+)''',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}${match.group(2)}$_mask',
      );
  final home =
      userHome ??
      _currentUserHome(environment: environment, isWindows: isWindows);
  if (home != null && home.isNotEmpty) {
    result = result.replaceAll(home, '~');
  }
  return result;
}

String? _currentUserHome({
  Map<String, String>? environment,
  bool? isWindows,
}) {
  final values = environment ?? Platform.environment;
  if (isWindows ?? Platform.isWindows) {
    final profile = _nonEmpty(values['USERPROFILE']);
    if (profile != null) {
      return profile;
    }
    final drive = _nonEmpty(values['HOMEDRIVE']);
    final homePath = _nonEmpty(values['HOMEPATH']);
    if (drive != null && homePath != null) {
      return '$drive$homePath';
    }
  }
  return _nonEmpty(values['HOME']);
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
