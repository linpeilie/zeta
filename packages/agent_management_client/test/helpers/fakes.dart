// Named fixture inputs stay readable at call sites.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:agent_management_client/agent_management_client.dart';

final class FakeProcessHandle implements CliProcessHandle {
  FakeProcessHandle({
    this.code = 0,
    List<int> stdoutBytes = const <int>[],
    List<int> stderrBytes = const <int>[],
    this.neverExits = false,
  }) : _stdoutBytes = stdoutBytes,
       _stderrBytes = stderrBytes;

  factory FakeProcessHandle.text({
    int code = 0,
    String stdout = '',
    String stderr = '',
  }) {
    return FakeProcessHandle(
      code: code,
      stdoutBytes: utf8.encode(stdout),
      stderrBytes: utf8.encode(stderr),
    );
  }

  final int code;
  final List<int> _stdoutBytes;
  final List<int> _stderrBytes;
  final bool neverExits;
  bool killed = false;

  @override
  Future<int> get exitCode =>
      neverExits ? Completer<int>().future : Future.value(code);

  @override
  bool kill() {
    killed = true;
    return true;
  }

  @override
  Stream<List<int>> get stderr => Stream<List<int>>.value(_stderrBytes);

  @override
  Stream<List<int>> get stdout => Stream<List<int>>.value(_stdoutBytes);
}

CliProcessRunner processRunnerFor(
  FakeProcessHandle handle, {
  void Function(String, List<String>, Map<String, String>?)? onStart,
}) {
  return CliProcessRunner(
    starter: (executable, arguments, {environment}) async {
      onStart?.call(executable, arguments, environment);
      return handle;
    },
  );
}

final class FakeManagementFileSystem implements AgentManagementFileSystem {
  final Map<String, AgentManagementFileMetadata> metadataByPath =
      <String, AgentManagementFileMetadata>{};
  final Map<String, String> textByPath = <String, String>{};
  final Map<String, List<String>> filesByDirectory = <String, List<String>>{};
  final Map<String, AgentManagementTextTail> tailsByPath =
      <String, AgentManagementTextTail>{};
  String? lastWritePath;
  String? lastWriteContents;
  String? backupPath;

  @override
  Future<List<String>> listFiles(
    String directoryPath, {
    bool recursive = false,
  }) async {
    return filesByDirectory[directoryPath] ?? const <String>[];
  }

  @override
  Future<AgentManagementFileMetadata> metadata(String path) async {
    return metadataByPath[path] ?? const AgentManagementFileMetadata.missing();
  }

  @override
  Future<String> readText(String path) async => textByPath[path] ?? '';

  @override
  Future<AgentManagementTextTail> readTextTail(
    String path, {
    required int maxBytes,
  }) async {
    return tailsByPath[path] ??
        const AgentManagementTextTail(contents: '', skippedPrefix: false);
  }

  @override
  Future<String?> writeTextAtomically(
    String path,
    String contents, {
    required String backupSuffix,
  }) async {
    lastWritePath = path;
    lastWriteContents = contents;
    textByPath[path] = contents;
    metadataByPath[path] = AgentManagementFileMetadata(
      exists: true,
      isFile: true,
      isLink: false,
      size: contents.length,
      modifiedAt: DateTime.utc(2026, 8, 20),
    );
    return backupPath;
  }
}
