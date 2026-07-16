part of 'codex_app_server_agent_provider.dart';

const _codexTargetVersion = _CodexSemanticVersion(0, 144, 5);
const _codexMinimumSupportedVersion = _CodexSemanticVersion(0, 142, 5);

AgentRuntimeInfo _codexRuntimeInfoFromInitialize(
  Object? value, {
  required AgentRuntimeScope runtimeScope,
  required String? configuredVersion,
}) {
  final result = _map(value);
  final userAgent = _string(result['userAgent']);
  final version =
      _CodexSemanticVersion.tryParse(userAgent) ??
      _CodexSemanticVersion.tryParse(configuredVersion);
  final compatibility = switch (version) {
    null => AgentRuntimeCompatibilityStatus.supportedWithLimitedCapabilities,
    final current when current < _codexMinimumSupportedVersion =>
      AgentRuntimeCompatibilityStatus.olderUnsupported,
    final current when current == _codexTargetVersion =>
      AgentRuntimeCompatibilityStatus.supported,
    final current when current > _codexTargetVersion =>
      AgentRuntimeCompatibilityStatus.newerUntested,
    _ => AgentRuntimeCompatibilityStatus.supportedWithLimitedCapabilities,
  };
  final platformFamily = _string(result['platformFamily']);
  final platformOs = _string(result['platformOs']);

  return AgentRuntimeInfo(
    runtimeId: runtimeScope.runtimeId,
    connectionEpoch: runtimeScope.connectionEpoch,
    protocolName: 'codex-app-server',
    protocolVersion: 'v2-stable/0.144.5',
    cliVersion: version?.toString(),
    serverUserAgent: userAgent,
    platform: <String?>[
      platformFamily,
      platformOs,
    ].whereType<String>().where((part) => part.isNotEmpty).join('/'),
    homePath: _string(result['codexHome']),
    experimentalApiEnabled: false,
    compatibilityStatus: compatibility,
  );
}

AgentProviderCapabilities _codexCapabilitiesForRuntime(
  AgentRuntimeInfo runtime,
) {
  final version = _CodexSemanticVersion.tryParse(runtime.cliVersion);
  final isUnsupported =
      runtime.compatibilityStatus ==
          AgentRuntimeCompatibilityStatus.olderUnsupported ||
      runtime.compatibilityStatus ==
          AgentRuntimeCompatibilityStatus.protocolMismatch;
  return AgentProviderCapabilities.codexAppServer.copyWith(
    canPrompt: !isUnsupported,
    canForkThreadAtTurn:
        !isUnsupported && version != null && version >= _codexTargetVersion,
    supportsPermissionProfileDiscovery: !isUnsupported,
    supportsPermissionProfileSelection: false,
  );
}

/// 仅用于协议兼容门控的三段式语义版本，不参与安装更新判断。
class _CodexSemanticVersion implements Comparable<_CodexSemanticVersion> {
  const _CodexSemanticVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static _CodexSemanticVersion? tryParse(String? value) {
    if (value == null) {
      return null;
    }
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(value);
    if (match == null) {
      return null;
    }
    return _CodexSemanticVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  @override
  int compareTo(_CodexSemanticVersion other) {
    final majorOrder = major.compareTo(other.major);
    if (majorOrder != 0) {
      return majorOrder;
    }
    final minorOrder = minor.compareTo(other.minor);
    if (minorOrder != 0) {
      return minorOrder;
    }
    return patch.compareTo(other.patch);
  }

  bool operator <(_CodexSemanticVersion other) => compareTo(other) < 0;

  bool operator <=(_CodexSemanticVersion other) => compareTo(other) <= 0;

  bool operator >(_CodexSemanticVersion other) => compareTo(other) > 0;

  bool operator >=(_CodexSemanticVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is _CodexSemanticVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
