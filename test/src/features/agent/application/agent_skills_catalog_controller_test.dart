import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_skills_catalog_controller.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('AgentSkillsCatalogController', () {
    test('loads catalog and filters query', () async {
      final port = _FakeSkillsPort();
      final controller = AgentSkillsCatalogController();
      addTearDown(controller.dispose);

      await controller.bind(
        providerId: 'codex',
        projectPath: '/repo',
        port: port,
      );

      expect(controller.state.status, AgentSkillsLoadStatus.ready);
      expect(controller.query('creator').single.name, 'skill-creator');
      expect(port.listCalls, 1);
    });

    test('force reloads on skillsChanged', () async {
      final port = _FakeSkillsPort();
      final controller = AgentSkillsCatalogController();
      addTearDown(controller.dispose);

      await controller.bind(
        providerId: 'codex',
        projectPath: '/repo',
        port: port,
      );
      expect(port.listCalls, 1);

      port.emitChanged();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(port.listCalls, greaterThanOrEqualTo(2));
      expect(port.lastForceReload, isTrue);
    });

    test('marks unavailable when port is null', () async {
      final controller = AgentSkillsCatalogController();
      addTearDown(controller.dispose);

      await controller.bind(
        providerId: 'grok',
        projectPath: '/repo',
        port: null,
      );

      expect(controller.state.status, AgentSkillsLoadStatus.unavailable);
      expect(controller.canUseSkills, isFalse);
    });
  });
}

final class _FakeSkillsPort implements AgentSkillsPort {
  final StreamController<void> _changed = StreamController<void>.broadcast();
  int listCalls = 0;
  bool? lastForceReload;

  @override
  Stream<void> get skillsChanged => _changed.stream;

  @override
  Future<AgentSkillsCatalog> listSkills({
    List<String> cwds = const <String>[],
    bool forceReload = false,
  }) async {
    listCalls += 1;
    lastForceReload = forceReload;
    return AgentSkillsCatalog(
      entries: [
        AgentSkillsCatalogEntry(
          cwd: cwds.isEmpty ? '/repo' : cwds.first,
          skills: const [
            AgentSkillMetadata(
              name: 'skill-creator',
              path: '/skills/skill-creator/SKILL.md',
              description: 'Create skills',
              enabled: true,
            ),
          ],
        ),
      ],
    );
  }

  void emitChanged() => _changed.add(null);
}
