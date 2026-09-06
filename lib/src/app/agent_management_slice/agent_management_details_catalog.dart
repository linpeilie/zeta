import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_agent_view.dart';
import 'package:zeta/src/features/agent_management/presentation/agent_management_details_catalog.dart';
import 'package:zeta/src/ui/core/system_file_manager.dart';

/// 同 Provider 的探测与显式连接检查拥有相互独立的资料槽。
enum AgentManagementDetailsKind { detection, explicitConnectionCheck }

/// 生命周期受 app 所有，只持有显示资源，不镜像业务状态。
final class AppAgentManagementDetailsCatalog
    implements AgentManagementDetailsCatalog {
  AppAgentManagementDetailsCatalog({
    Future<void> Function(String)? copy,
    Future<void> Function(String)? openDirectory,
  }) : _copy =
           copy ?? ((value) => Clipboard.setData(ClipboardData(text: value))),
       _openDirectory = openDirectory ?? openPathInSystemFileManager;
  final Future<void> Function(String) _copy;
  final Future<void> Function(String) _openDirectory;
  final _resources =
      <
        AgentManagementDetailsHandle,
        ({String? executable, String diagnostic})
      >{};
  final _confirmed =
      <(String, AgentManagementDetailsKind), AgentManagementDetailsHandle>{};
  bool _closed = false;
  int get resourceCount => _resources.length;

  AgentManagementDetailsHandle? stage({
    String? executable,
    String? diagnostic,
  }) {
    if (_closed) throw UnsupportedError('Management details are closed');
    if (executable == null && (diagnostic == null || diagnostic.isEmpty)) {
      return null;
    }
    final handle = AgentManagementDetailsHandle();
    _resources[handle] = (
      executable: executable,
      diagnostic: safeManagementText(diagnostic) ?? '',
    );
    return handle;
  }

  void confirm(
    String id,
    AgentManagementDetailsKind kind,
    AgentManagementDetailsHandle? handle,
  ) {
    if (_closed) {
      discard(handle);
      return;
    }
    final old = _confirmed.remove((id, kind));
    if (old != null && !identical(old, handle)) _resources.remove(old);
    if (handle != null && _resources.containsKey(handle)) {
      _confirmed[(id, kind)] = handle;
    }
  }

  void discard(AgentManagementDetailsHandle? handle) {
    _resources.remove(handle);
  }

  void close() {
    _closed = true;
    _confirmed.clear();
    _resources.clear();
  }

  @override
  AgentManagementDetailDisplay display(AgentManagementDetailsHandle? handle) {
    final resource = _resources[handle];
    if (_closed || resource == null) {
      return const AgentManagementDetailDisplay(available: false);
    }
    final path = resource.executable;
    return AgentManagementDetailDisplay(
      available: true,
      executableLocationLabel: path == null
          ? ''
          : '…/${safeManagementText(path.replaceAll('\\', '/').split('/').last)}',
      diagnosticDescription: resource.diagnostic,
    );
  }

  String _executable(AgentManagementDetailsHandle handle) {
    final path = _resources[handle]?.executable;
    if (_closed || path == null) {
      throw UnsupportedError('Executable details are unavailable');
    }
    return path;
  }

  @override
  Future<void> copyExecutableLocation(
    AgentManagementDetailsHandle handle,
  ) async {
    await _copy(_executable(handle));
  }

  @override
  Future<void> openExecutableDirectory(
    AgentManagementDetailsHandle handle,
  ) async {
    await _openDirectory(File(_executable(handle)).parent.path);
  }
}

/// 白名单文本二次脱敏；绝不把任意异常的 toString 用作公开失败文案。
String? safeManagementText(String? value) {
  if (value == null) return null;
  return redactSensitiveText(
    value,
    homeDirectory: Platform.environment['HOME'],
  ).replaceAll(RegExp(r'(?:[A-Za-z]:[\\/]|/|~/)[^\s,;]+'), '…');
}

final appAgentManagementDetailsCatalogProvider =
    Provider<AppAgentManagementDetailsCatalog>((ref) {
      final catalog = AppAgentManagementDetailsCatalog();
      ref.onDispose(catalog.close);
      return catalog;
    });
