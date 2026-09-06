import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _ownerPath =
    'lib/src/features/agent_management/application/agent_management_slice/agent_management_slice_notifier.dart';
const _runnerPath =
    'lib/src/app/agent_management_slice/agent_management_slice_runner.dart';
const _presentationPath = 'lib/src/features/agent_management/presentation';

List<String> _violations(
  String source, {
  bool presentation = false,
  bool runner = false,
}) {
  final visitor = _OwnershipVisitor(presentation: presentation, runner: runner);
  parseString(content: source).unit.accept(visitor);
  return visitor.violations;
}

final class _OwnershipVisitor extends RecursiveAstVisitor<void> {
  _OwnershipVisitor({required this.presentation, required this.runner});
  final bool presentation, runner;
  final violations = <String>[];

  @override
  void visitNamedType(NamedType node) {
    final name = node.name.lexeme;
    if ([
          'AgentManagementSliceStore',
          'AgentManagementSliceComposition',
          '_DeferredAgentManagementSliceRunner',
        ].contains(name) ||
        (runner && ['Ref', 'AgentManagementSliceNotifier'].contains(name)) ||
        (presentation &&
            [
              'AgentManagementResultSink',
              'AgentManagementOwnerLifecycle',
            ].contains(name))) {
      violations.add('forbidden type $name');
    }
    super.visitNamedType(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (presentation &&
        node.extendsClause?.superclass.name.lexeme == 'Notifier') {
      violations.add('presentation state owner');
    }
    if (runner) {
      for (final member in node.body.members.whereType<MethodDeclaration>()) {
        if (!member.name.lexeme.startsWith('_') &&
            !['run', 'validateConfiguration'].contains(member.name.lexeme)) {
          violations.add('runner business member');
        }
        if (member.name.lexeme == 'run' &&
            member.returnType?.toSource() != 'Future<void>') {
          violations.add('runner must return execution future');
        }
      }
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if ((runner && node.methodName.name == 'unawaited') ||
        (presentation &&
            [
              'stopAcceptingCommandsAndSettleWaiters',
              'drainExecutions',
              'runtimeFactsReplaced',
              'initializationSucceeded',
              'configurationSaved',
              'logsLoaded',
            ].contains(node.methodName.name))) {
      violations.add('forbidden call ${node.methodName.name}');
    }
    super.visitMethodInvocation(node);
  }
}

void main() {
  test('management has one application owner and no presentation mirror', () {
    final owner = File(_ownerPath).readAsStringSync();
    final unit = parseString(content: owner).unit;
    final declarations = unit.declarations
        .whereType<ClassDeclaration>()
        .where(
          (node) => node.extendsClause?.superclass.name.lexeme == 'Notifier',
        )
        .toList();
    expect(declarations, hasLength(1));
    expect(
      declarations.single.namePart.typeName.lexeme,
      'AgentManagementSliceNotifier',
    );
    final build = declarations.single.body.members
        .whereType<MethodDeclaration>()
        .singleWhere((member) => member.name.lexeme == 'build');
    expect(build.body.toSource(), isNot(contains('ref.watch')));
    final providers = unit.declarations
        .whereType<TopLevelVariableDeclaration>()
        .expand((node) => node.variables.variables)
        .where((node) => node.name.lexeme == 'agentManagementSliceProvider')
        .toList();
    expect(providers, hasLength(1));
    expect(providers.single.initializer!.toSource(), isNot(contains('family')));
    expect(
      providers.single.initializer!.toSource(),
      isNot(contains('autoDispose')),
    );
    expect(_violations(owner), isEmpty);
    final presentation = Directory(_presentationPath)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    expect(presentation, isNotEmpty);
    for (final file in presentation) {
      expect(
        _violations(file.readAsStringSync(), presentation: true),
        isEmpty,
        reason: file.path,
      );
    }
    expect(
      File(_ownerPath.replaceAll('notifier.dart', 'store.dart')).existsSync(),
      isFalse,
    );
    expect(
      _violations(File(_runnerPath).readAsStringSync(), runner: true),
      isEmpty,
    );
  });

  test('guard accepts read-only selectors and scoped Widget state', () {
    expect(
      _violations('''
      final selected = Provider((ref) => ref.watch(agentManagementSliceProvider.select((state) => state.selectedAgentId)));
      class Editor extends ConsumerState<EditorWidget> { bool dirty = false; }
      // AgentManagementSliceStore and Notifier in a comment are not ownership.
    ''', presentation: true),
      isEmpty,
    );
    expect(
      _violations('''
      class Runner { final AgentManagementResultSink sink; Future<void> run(Object effect) => _load(effect); String? validateConfiguration(String id, String content) => null; Future<void> _load(Object effect) async {} }
    ''', runner: true),
      isEmpty,
    );
  });

  test(
    'guard rejects renamed mirrors, old store, result writes and owner close in UI',
    () {
      expect(
        _violations(
          'class Renamed extends Notifier<AgentManagementSliceState> {}',
          presentation: true,
        ),
        isNotEmpty,
      );
      expect(
        _violations(
          'class Widget { final AgentManagementSliceStore old; }',
          presentation: true,
        ),
        isNotEmpty,
      );
      expect(
        _violations(
          'void onTap() { commands.stopAcceptingCommandsAndSettleWaiters(); sink.configurationSaved(a, b, c, d); }',
          presentation: true,
        ),
        hasLength(2),
      );
    },
  );

  test('guard rejects runner state ownership and hidden physical execution', () {
    expect(
      _violations(
        'class Runner { final Ref ref; final AgentManagementSliceNotifier owner; void run(Object effect) { unawaited(load()); } void selectAgent(String id) {} }',
        runner: true,
      ),
      hasLength(5),
    );
  });
}
