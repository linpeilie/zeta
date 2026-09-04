import 'dart:io';

import 'package:test/test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk_testing.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

void main() {
  test('MemoryAgentProviderConfigStore 保存 typed 设置', () async {
    const initial = AgentProviderSettings();
    final store = MemoryAgentProviderConfigStore(initial);
    const next = AgentProviderSettings(activeProviderId: 'next');

    await store.save(next);

    expect(await store.load(), same(next));
  });

  test('FileTestStorageService 串行原子替换并清理临时文件', () async {
    final directory = await Directory.systemTemp.createTemp(
      'zeta-provider-sdk-storage-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/state.json');
    final storage = FileTestStorageService(file);

    await Future.wait(<Future<void>>[
      storage.write('first'),
      storage.write('second'),
    ]);

    expect(await storage.read(), 'second');
    expect(
      directory.listSync().whereType<File>().map((item) => item.path),
      <String>[file.path],
    );
  });

  test('RecordingZetaLoggerFactory 按 scope 记录脱敏消息', () {
    final factory = RecordingZetaLoggerFactory();
    ZetaLogging.install(factory.call);
    addTearDown(ZetaLogging.reset);

    zetaLoggerFor('zeta.test.provider').i('ready');

    expect(factory.records, hasLength(1));
    expect(factory.records.single.scope, 'zeta.test.provider');
    expect(factory.records.single.level, 'info');
    expect(factory.records.single.message, 'ready');
  });
}
