import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/data/codex_cli_locator.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent_management/data/cli_process_runner.dart';
import 'package:zeta/src/features/agent_management/data/codex_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';

void main() {
  group('CodexAgentManagementRepository', () {
    late Directory codexHome;
    late CodexAgentManagementRepository repository;

    setUp(() async {
      codexHome = await Directory.systemTemp.createTemp(
        'zeta-agent-management-test-',
      );
      final registry = AgentProviderRuntimeRegistry(
        providerFactory: const _ThrowingProviderFactory(),
      );
      addTearDown(registry.close);
      repository = CodexAgentManagementRepository(
        runtimeRegistry: registry,
        codexHomeProvider: () => codexHome.path,
      );
    });

    tearDown(() async {
      if (await codexHome.exists()) {
        await codexHome.delete(recursive: true);
      }
    });

    test('compares semantic versions conservatively', () {
      expect(isNewerVersion('0.131.0', '0.130.0'), isTrue);
      expect(isNewerVersion('1.0.0', '0.130.0'), isTrue);
      expect(isNewerVersion('0.130.0', '0.130.0'), isFalse);
      expect(isNewerVersion('0.129.9', '0.130.0'), isFalse);
      expect(isNewerVersion('latest', '0.130.0'), isFalse);
    });

    test('masks configuration and redacts log credentials', () {
      final masked = maskSensitiveConfiguration('''
model = "gpt"
api_key = "sk-secret-value-123456"
refreshToken = "refresh-secret"
''');
      expect(masked, contains('model = "gpt"'));
      expect(masked, isNot(contains('sk-secret-value-123456')));
      expect(masked, isNot(contains('refresh-secret')));

      final redacted = redactLogLine(
        'Authorization: Bearer abc.def.ghi token=secret-value '
        'sk-abcdefghijklmnop',
      );
      expect(redacted, isNot(contains('abc.def.ghi')));
      expect(redacted, isNot(contains('secret-value')));
      expect(redacted, isNot(contains('abcdefghijklmnop')));
    });

    test(
      'saves valid TOML through a backup and reloads the snapshot',
      () async {
        final config = File(repository.configPath);
        await config.writeAsString('model = "gpt-old"\n');
        final original = await repository.readConfiguration();

        final result = await repository.saveConfiguration(
          original: original,
          content: 'model = "gpt-new"\n',
        );

        expect(await config.readAsString(), 'model = "gpt-new"\n');
        expect(result.document.content, 'model = "gpt-new"\n');
        expect(result.backupPath, isNotNull);
        expect(
          await File(result.backupPath!).readAsString(),
          'model = "gpt-old"\n',
        );
      },
    );

    test('rejects invalid TOML without changing the original file', () async {
      final config = File(repository.configPath);
      await config.writeAsString('model = "gpt"\n');
      final original = await repository.readConfiguration();

      expect(
        () => repository.saveConfiguration(
          original: original,
          content: 'model = [\n',
        ),
        throwsA(isA<AgentConfigurationValidationException>()),
      );
      expect(await config.readAsString(), 'model = "gpt"\n');
    });

    test('detects an external modification before saving', () async {
      final config = File(repository.configPath);
      await config.writeAsString('model = "one"\n');
      final original = await repository.readConfiguration();
      await config.writeAsString('model = "external"\n');

      expect(
        () => repository.saveConfiguration(
          original: original,
          content: 'model = "local"\n',
        ),
        throwsA(isA<AgentConfigurationConflictException>()),
      );
      expect(await config.readAsString(), 'model = "external"\n');
    });
  });

  // 04-目标态与步骤.md §S7：连接检测是"会话建立前"的一次性探测，_probeProvider
  // 必须显式绑定全局实例，不依赖 registry 的默认 scope。
  group('testConnection 显式绑定 global scope（S7）', () {
    test('探测用的实例注册在全局 scope 下；探测结束租约归零', () async {
      final factory = _ProbeProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);
      final repository = CodexAgentManagementRepository(
        locator: const _FakeLocator(),
        processRunner: const _LoggedInProcessRunner(),
        runtimeRegistry: registry,
      );

      final (result, _) = await repository.testConnection(
        providerConfig: AgentProviderConfig.defaultCodex,
      );

      expect(result.success, isTrue);
      expect(registry.debugLeaseCount, 0, reason: '探测借了要还，不能残留租约');
      expect(factory.providers, hasLength(1));

      // 探测只允许留下唯一的全局实例；session 隔离由下一条用例从行为侧验证。
      expect(registry.debugProviderCount, 1);
    });

    test('探测拿到的实例与某个会话 scope 的实例不是同一个', () async {
      final factory = _ProbeProviderFactory();
      final registry = AgentProviderRuntimeRegistry(providerFactory: factory);
      addTearDown(registry.close);
      final repository = CodexAgentManagementRepository(
        locator: const _FakeLocator(),
        processRunner: const _LoggedInProcessRunner(),
        runtimeRegistry: registry,
      );

      await repository.testConnection(
        providerConfig: AgentProviderConfig.defaultCodex,
      );
      final probedProvider = factory.providers.single;

      final sessionLease = await registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: const AgentProviderRuntimeScopeKey.session('entry-a'),
      );
      expect(identical(sessionLease.provider, probedProvider), isFalse);
      await sessionLease.release();
    });
  });
}

class _ThrowingProviderFactory implements AgentProviderFactory {
  const _ThrowingProviderFactory();

  @override
  AgentProvider create(AgentProviderConfig config) {
    throw UnsupportedError('Provider creation is not used by these tests.');
  }
}

/// 跳过真实文件系统探测，直接返回一个不需要真的可执行的伪命令——探测流程
/// 后续只经过同样被替身的 [_LoggedInProcessRunner] 和 provider factory，不会
/// 真的 spawn 进程。
class _FakeLocator implements CodexCliLocator {
  const _FakeLocator();

  @override
  Map<String, String>? get environment => null;

  @override
  Future<ResolvedCliCommand?> locate(AgentProviderConfig config) async {
    return const ResolvedCliCommand(
      displayPath: '/fake/codex',
      executable: '/fake/codex',
    );
  }

  @override
  Future<ResolvedCliCommand?> resolvePath(String path) async {
    return const ResolvedCliCommand(
      displayPath: '/fake/codex',
      executable: '/fake/codex',
    );
  }
}

/// 固定返回"已登录"，不真的 spawn 子进程。
class _LoggedInProcessRunner implements CliProcessRunner {
  const _LoggedInProcessRunner();

  @override
  Future<CliProcessResult> run(
    ResolvedCliCommand command,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
    int maxOutputCharacters = 64 * 1024,
    Map<String, String>? environment,
  }) async {
    return const CliProcessResult(
      exitCode: 0,
      stdout: 'logged in',
      stderr: '',
      elapsed: Duration.zero,
    );
  }
}

/// 每次 create 返回新实例，capabilities 全关（不声明模型目录支持），让
/// `_probeProvider` 走最短路径：不触碰 `fetchAgentProviderModels`。
class _ProbeProviderFactory implements AgentProviderFactory {
  final List<_ProbeFakeProvider> providers = <_ProbeFakeProvider>[];

  @override
  AgentProvider create(AgentProviderConfig config) {
    final provider = _ProbeFakeProvider(config);
    providers.add(provider);
    return provider;
  }
}

class _ProbeFakeProvider extends Fake implements AgentProvider {
  _ProbeFakeProvider(this.config);

  @override
  final AgentProviderConfig config;

  @override
  AgentProviderCapabilities get capabilities =>
      const AgentProviderCapabilities();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}
}
