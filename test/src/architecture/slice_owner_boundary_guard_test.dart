import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

// Persistent application owners; selectors never own runtime resources.
const _base = 'lib/src/features/project_threads/';
const _owner =
    '${_base}application/project_threads_slice/project_threads_slice_notifier.dart';
const _app =
    'lib/src/app/project_threads_slice/project_threads_slice_composition.dart';
const _runner =
    'lib/src/app/project_threads_slice/project_threads_slice_runner.dart';

List<String> _violations(
  String source, {
  bool presentation = false,
  bool runner = false,
  bool owner = false,
  bool borrower = false,
}) {
  final visitor = _BoundaryVisitor(
    presentation: presentation,
    runner: runner,
    owner: owner,
    borrower: borrower,
  );
  parseString(content: source).unit.accept(visitor);
  return visitor.failures;
}

final class _BoundaryVisitor extends RecursiveAstVisitor<void> {
  _BoundaryVisitor({
    required this.presentation,
    required this.runner,
    required this.owner,
    required this.borrower,
  });
  final bool presentation, runner, owner, borrower;
  final failures = <String>[];

  @override
  void visitNamedType(NamedType node) {
    final name = node.name.lexeme;
    if ([
          'ProjectThreadsSliceStore',
          'ProjectThreadsSliceComposition',
          '_DeferredProjectThreadsSliceRunner',
        ].contains(name) ||
        (runner && ['Ref', 'ProjectThreadsSliceNotifier'].contains(name))) {
      failures.add('type $name');
    }
    super.visitNamedType(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (presentation &&
        node.extendsClause?.superclass.name.lexeme == 'Notifier') {
      failures.add('presentation owner');
    }
    if (node.namePart.typeName.lexeme.startsWith('_DeferredProjectThreads')) {
      failures.add('deferred runner');
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (owner && ['subscribe', '_notifyListeners'].contains(node.name.lexeme)) {
      failures.add('manual publication');
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (owner && ['_listeners', '_state'].contains(node.name.lexeme)) {
      failures.add('copied state');
    }
    if (node.name.lexeme == 'projectThreadsSliceProvider') {
      final code = node.initializer?.toSource() ?? '';
      if (code.contains('.family') ||
          code.contains('.autoDispose') ||
          code.contains('isAutoDispose: true')) {
        failures.add('unstable owner lifetime');
      }
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if ([
      'ProjectThreadsSliceStore',
      'ProjectThreadsSliceComposition',
      '_DeferredProjectThreadsSliceRunner',
    ].contains(name)) {
      failures.add('old owner creation');
    }
    if (owner &&
        (name == 'scheduleMicrotask' ||
            (name == 'watch' && node.target?.toSource() == 'ref'))) {
      failures.add('owner rebuild or mirror');
    }
    if (presentation &&
        [
          'stopAcceptingCommandsAndSettleWaiters',
          'drainExecutions',
          'ProjectThreadsSliceRunner',
          'ProjectThreadsSliceNotifier',
        ].contains(name)) {
      failures.add('UI owns execution');
    }
    if (borrower && name == 'AgentConversationBindingManager') {
      failures.add('borrower creates manager');
    }
    if (borrower &&
        name == 'close' &&
        node.target?.toSource().contains('bindingManager') == true) {
      failures.add('borrower closes manager');
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final name = node.constructorName.type.name.lexeme;
    if (borrower && name == 'AgentConversationBindingManager') {
      failures.add('borrower creates manager');
    }
    if (presentation &&
        [
          'ProjectThreadsSliceRunner',
          'ProjectThreadsSliceNotifier',
        ].contains(name)) {
      failures.add('UI owns execution');
    }
    super.visitInstanceCreationExpression(node);
  }
}

void main() {
  test(
    'Conversation and Workspace have persistent owners and no reverse Widget binding',
    () {
      const conversation =
          'lib/src/features/agent/application/conversation_slice/';
      const workspace = 'lib/src/app/conversation_workspace_slice/';
      for (final path in [
        '${conversation}agent_conversation_slice_notifier.dart',
        '${workspace}agent_conversation_workspace_notifier.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          _conversationViolations(
            source,
            owner: true,
            workspace: path.startsWith(workspace),
          ),
          isEmpty,
          reason: path,
        );
        final classes = parseString(content: source).unit.declarations
            .whereType<ClassDeclaration>()
            .where(
              (node) =>
                  node.extendsClause?.superclass.name.lexeme == 'Notifier',
            );
        expect(classes, hasLength(1));
      }
      final ownerSource = File(
        '${conversation}agent_conversation_slice_notifier.dart',
      ).readAsStringSync();
      expect(ownerSource, contains('_projectionRetention = ref.keepAlive()'));
      expect(ownerSource, contains('releaseClosedProjectionRetention'));
      final lifetimeSource = File(
        '${workspace}conversation_slice_lifetime_coordinator.dart',
      ).readAsStringSync();
      expect(
        lifetimeSource,
        contains('owner.releaseClosedProjectionRetention()'),
      );
      expect(
        _conversationViolations(
          File(
            '${conversation}agent_conversation_command_effect_runner.dart',
          ).readAsStringSync(),
          runner: true,
        ),
        isEmpty,
      );
      final home = File(
        'lib/src/ui/features/ide/views/ide_home.dart',
      ).readAsStringSync();
      expect(_conversationViolations(home, ui: true), isEmpty);
      expect(home, contains('ref.read(workbenchSessionProvider)'));
      final shellUnit = parseString(
        content: File(
          'lib/src/app/shell/ide_shell_controller.dart',
        ).readAsStringSync(),
      ).unit;
      final shell = shellUnit.declarations.whereType<ClassDeclaration>().single;
      final constructor = shell.body.members
          .whereType<ConstructorDeclaration>()
          .single;
      expect(constructor.body.toSource(), isNot(contains('unawaited')));
      expect(constructor.body.toSource(), isNot(contains('ensureDraftEntry')));
      for (final path in [
        '${conversation}agent_conversation_slice_store.dart',
        '${conversation}agent_conversation_slice_store_registry.dart',
        '${workspace}agent_conversation_workspace_store.dart',
      ]) {
        expect(File(path).existsSync(), isFalse);
      }
      expect(
        _conversationViolations(
          File(
            '${workspace}agent_conversation_workspace_providers.dart',
          ).readAsStringSync(),
        ),
        isEmpty,
      );
      expect(
        File(
          'lib/src/app/composition/zeta_state_snapshot.dart',
        ).readAsStringSync(),
        isNot(contains('ZetaShellStateSnapshotRelay')),
      );
    },
  );

  test(
    'Conversation guard rejects mirrors, mutable registries, unstable keys and UI resource ownership',
    () {
      for (final source in [
        'void copy() { state = store.state; }',
        'final x = AgentConversationSliceStore();',
        'class AgentConversationSliceStoreRegistry {}',
        'class _DeferredConversationRunner {}',
        'void dispose() { _shellController.dispose(); }',
        'class A { AgentConversationWorkspaceStoreRegistry registry; }',
        'final agentConversationSliceOwnerProvider = NotifierProvider.family(make);',
        'final agentConversationSliceOwnerProvider = NotifierProvider.autoDispose.family<N, S, AgentConversationOwnerKey>(make);',
        'final agentConversationWorkspaceProvider = NotifierProvider(make, isAutoDispose: true);',
        'class N { final _listeners = []; void build() { ref.watch(inputs); } }',
        'void build() { IdeShellController(); lifetimes.closeEntry(key); }',
        "import 'agent_conversation_slice_notifier.dart';",
      ]) {
        expect(
          _conversationViolations(
            source,
            owner: true,
            workspace: true,
            ui: true,
          ),
          isNotEmpty,
          reason: source,
        );
      }
      expect(
        _conversationViolations(
          'class Runner { final Ref ref; void run() { ref.read(owner); } }',
          runner: true,
        ),
        isNotEmpty,
      );
      expect(
        _conversationViolations(
          'final selector = Provider((ref) => ref.watch(region)); class Local extends State<Card> {}',
          ui: true,
        ),
        isEmpty,
      );
      expect(
        _conversationViolations(
          'void detach() { core.removeListener(listener); }',
        ),
        isEmpty,
      );
    },
  );

  test('Project Threads production has one persistent application owner', () {
    final owner = File(_owner).readAsStringSync();
    final unit = parseString(content: owner).unit;
    final notifiers = unit.declarations.whereType<ClassDeclaration>().where(
      (n) => n.extendsClause?.superclass.name.lexeme == 'Notifier',
    );
    expect(notifiers, hasLength(1));
    expect(
      notifiers.single.namePart.typeName.lexeme,
      'ProjectThreadsSliceNotifier',
    );
    expect(_violations(owner, owner: true), isEmpty);
    expect(
      File(_owner.replaceAll('notifier.dart', 'store.dart')).existsSync(),
      isFalse,
    );
    expect(_violations(File(_app).readAsStringSync()), isEmpty);
    expect(
      _violations(File(_runner).readAsStringSync(), runner: true),
      isEmpty,
    );
    final files = Directory('${_base}presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    for (final file in files) {
      expect(
        _violations(file.readAsStringSync(), presentation: true),
        isEmpty,
        reason: file.path,
      );
    }
    for (final file in [
      'lib/src/app/shell/ide_shell_controller.dart',
      'lib/src/app/conversation_workspace_slice/agent_conversation_workspace_notifier.dart',
    ]) {
      expect(
        _violations(File(file).readAsStringSync(), borrower: true),
        isEmpty,
        reason: file,
      );
    }
    final home = File(
      'lib/src/ui/features/ide/views/ide_home.dart',
    ).readAsStringSync();
    expect(_violations(home, presentation: true), isEmpty);
    expect(home, isNot(contains('projectThreadsSliceStoreProvider')));
    final composition = File(_app).readAsStringSync();
    expect(composition, contains('agentConversationBindingManagerProvider'));
    expect(
      File(
        'lib/src/app/composition/agent_session_resource_providers.dart',
      ).readAsStringSync(),
      contains('AgentConversationBindingManager('),
    );
    expect(composition, contains('ProjectThreadsSliceRunner('));
  });

  test('guard accepts selectors, typed sink and subscription resources', () {
    expect(
      _violations(
        'final view = Provider((ref) => ref.watch(projectThreadsSliceProvider.select((s) => s.stateFor(path)))); class Card extends ConsumerState<View> {}',
        presentation: true,
      ),
      isEmpty,
    );
    expect(
      _violations(
        'class Runner { final ProjectThreadsStateOwner sink; void run(Effect e) {} Future<void> drainExecutions() async {} }',
        runner: true,
      ),
      isEmpty,
    );
  });

  test('guard rejects mirrors, mutable owner lifetime and listener lists', () {
    for (final source in [
      'class Mirror extends Notifier<State> {}',
      'final x = ProjectThreadsSliceStore();',
      'class _DeferredProjectThreadsSliceRunner {}',
      'final projectThreadsSliceProvider = NotifierProvider.family(make);',
      'final projectThreadsSliceProvider = NotifierProvider(make, isAutoDispose: true);',
      'class Owner { final _listeners = []; void subscribe() {} void build() { ref.watch(deps); scheduleMicrotask(publish); } }',
    ]) {
      expect(
        _violations(source, presentation: true, owner: true),
        isNotEmpty,
        reason: source,
      );
    }
  });

  test('guard rejects runner owner access and UI resource ownership', () {
    expect(
      _violations(
        'class Runner { final Ref ref; final ProjectThreadsSliceNotifier owner; }',
        runner: true,
      ),
      hasLength(2),
    );
    expect(
      _violations(
        'void build() { ProjectThreadsSliceRunner(); owner.drainExecutions(); owner.stopAcceptingCommandsAndSettleWaiters(); }',
        presentation: true,
      ),
      hasLength(3),
    );
    expect(
      _violations(
        'void start() { AgentConversationBindingManager(); bindingManager.close(); }',
        borrower: true,
      ),
      hasLength(2),
    );
  });
}

List<String> _conversationViolations(
  String source, {
  bool owner = false,
  bool workspace = false,
  bool ui = false,
  bool runner = false,
}) {
  final visitor = _ConversationBoundaryVisitor(
    owner: owner,
    workspace: workspace,
    ui: ui,
    runner: runner,
  );
  final unit = parseString(content: source).unit;
  unit.accept(visitor);
  final hasPhysicalOwner = unit.declarations
      .whereType<TopLevelVariableDeclaration>()
      .any(
        (node) => node.variables.variables.any(
          (variable) =>
              variable.name.lexeme == 'agentConversationSliceOwnerProvider',
        ),
      );
  if (hasPhysicalOwner &&
      !source.contains('_projectionRetention = ref.keepAlive()')) {
    visitor.failures.add('conversation owner lacks explicit retention');
  }
  return visitor.failures;
}

final class _ConversationBoundaryVisitor extends RecursiveAstVisitor<void> {
  _ConversationBoundaryVisitor({
    required this.owner,
    required this.workspace,
    required this.ui,
    required this.runner,
  });
  final bool owner, workspace, ui, runner;
  final failures = <String>[];
  static const retired = {
    'AgentConversationSliceStore',
    'AgentConversationSliceStoreRegistry',
    'AgentConversationWorkspaceStore',
    'AgentConversationWorkspaceStoreRegistry',
    'ZetaShellStateSnapshotRelay',
  };
  static const uiOwners = {
    'IdeShellController',
    'AgentConversationWorkspaceNotifier',
    'AgentConversationSliceNotifier',
    'ConversationSliceLifetimeCoordinator',
    'AgentConversationCommandEffectRunner',
  };
  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (retired.contains(node.namePart.typeName.lexeme) ||
        node.namePart.typeName.lexeme.startsWith('_Deferred')) {
      failures.add('retired owner declaration');
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitNamedType(NamedType node) {
    final name = node.name.lexeme;
    if (retired.contains(name) ||
        (runner &&
            (name == 'Ref' || name == 'AgentConversationSliceNotifier'))) {
      failures.add('owner type $name');
    }
    super.visitNamedType(node);
  }

  @override
  void visitImportDirective(ImportDirective node) {
    final uri = node.uri.stringValue ?? '';
    if (workspace &&
        (uri.contains('agent_conversation_slice_notifier.dart') ||
            uri.contains('workbench_session_providers.dart'))) {
      failures.add('workspace dependency cycle');
    }
    super.visitImportDirective(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (node.leftHandSide.toSource() == 'state' &&
        RegExp(r'\bstore\.state\b').hasMatch(node.rightHandSide.toSource())) {
      failures.add('mirror');
    }
    super.visitAssignmentExpression(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (owner && ['_state', '_listeners'].contains(node.name.lexeme)) {
      failures.add('second publication owner');
    }
    if ([
      'agentConversationSliceOwnerProvider',
      'agentConversationWorkspaceProvider',
    ].contains(node.name.lexeme)) {
      final code = node.initializer?.toSource() ?? '';
      if (node.name.lexeme == 'agentConversationWorkspaceProvider' &&
          (code.contains('autoDispose') ||
              code.contains('isAutoDispose: true'))) {
        failures.add('automatic resource lifetime');
      }
      if (node.name.lexeme == 'agentConversationSliceOwnerProvider' &&
          !code.contains('AgentConversationOwnerKey')) {
        failures.add('unstable family identity');
      }
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (ui &&
        [
          'dispose',
          'close',
          'release',
          'stopAcceptingCommands',
        ].contains(name) &&
        [
          '_shellController',
          'shell',
          'bindingManager',
          'runtimeRegistry',
          'bindingLease',
          'workspace',
        ].contains(node.target?.toSource())) {
      failures.add('UI closes application resources');
    }
    if (retired.contains(name) || (ui && uiOwners.contains(name))) {
      failures.add('owner construction');
    }
    if (ui &&
        [
          'closeForEntryRelease',
          'closeAllEntries',
          'closeEntry',
          'closeCommandIngress',
        ].contains(name)) {
      failures.add('UI releases entry');
    }
    if (owner && node.target?.toSource() == 'ref' && name == 'watch') {
      failures.add('owner rebuilds from inputs');
    }
    if (runner && node.target?.toSource() == 'ref') {
      failures.add('runner reads Ref');
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (retired.contains(node.constructorName.type.name.lexeme) ||
        (ui && uiOwners.contains(node.constructorName.type.name.lexeme))) {
      failures.add('owner construction');
    }
    super.visitInstanceCreationExpression(node);
  }
}
