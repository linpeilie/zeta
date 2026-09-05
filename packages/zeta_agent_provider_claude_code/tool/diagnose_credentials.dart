import 'dart:convert';
import 'dart:io';

import 'package:zeta_agent_provider_claude_code/src/datasources/claude_code/claude_code_credentials_service.dart';
import 'package:zeta_agent_provider_claude_code/src/datasources/claude_code/claude_code_macos_keychain_source.dart';

/// Read-only diagnostics. Never call ensureFresh(), write(), or an HTTP client.
Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty &&
      (arguments.length != 2 || arguments.first != '--config-dir')) {
    stderr.writeln('Usage: diagnose_credentials.dart [--config-dir DIRECTORY]');
    exitCode = 64;
    return;
  }
  final environment = {...Platform.environment};
  if (arguments.isNotEmpty) environment['CLAUDE_CONFIG_DIR'] = arguments[1];
  final report = <String, Object?>{
    'mode': 'readOnly',
    'refreshAttempted': false,
  };
  try {
    final secure = ClaudeCodeMacOsKeychainSource(environment: environment);
    final service = LocalClaudeCodeCredentialsService(
      environment: environment,
      secureSource: secure,
    );
    final result = await service.read();
    report['status'] = result.status.name;
    report['source'] = result.source?.name;
    final credentials = result.credentials;
    if (credentials != null) {
      report['expiry'] = credentials.expiryAt(DateTime.now()).name;
      report['refreshTokenPresent'] = credentials.refreshToken != null;
    }
    if (result.source == ClaudeCodeCredentialsSource.keychain &&
        result.status == ClaudeCodeCredentialsStatus.available) {
      final raw = await secure.read();
      if (raw == null) {
        report['preflight'] = 'sourceChanged';
      } else {
        secure.validateWrite(raw);
        // This checks only the command format/size, not write permission.
        report['preflight'] = 'passed';
      }
    } else {
      report['preflight'] = 'notChecked';
    }
  } on ClaudeCodeSecureCredentialsWriteException catch (error) {
    report['stage'] = error.stage.name;
    report['reason'] = error.reason.name;
    exitCode = 1;
  } catch (_) {
    report['diagnostic'] = 'unavailable';
    exitCode = 1;
  }
  stdout.writeln(jsonEncode(report));
}
