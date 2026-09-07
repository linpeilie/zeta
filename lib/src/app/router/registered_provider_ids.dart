import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';

/// 已登记 provider id，供 draft 路由同步校验。
final registeredProviderIdsProvider = Provider<Set<String>>(
  (ref) => zetaAgentProviderDefinitionCatalog.definitions
      .map((definition) => definition.providerId)
      .toSet(),
  name: 'registeredProviderIds',
);
