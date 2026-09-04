import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:zeta/src/features/agent/application/agent_composer_attachment_port.dart';
import 'package:zeta/src/features/agent/data/agent_composer_attachment_store.dart';

/// 生产剪贴板图片暂存。只有 `lib/main.dart` 装它，测试装内存 fake。
Override systemComposerAttachmentOverride() {
  return agentComposerAttachmentPortProvider.overrideWithValue(
    AgentComposerAttachmentStore(),
  );
}
