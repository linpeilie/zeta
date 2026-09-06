import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

// WP-3P boundaries. Conversation/Workspace mirror removal remains WP-3C.
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
      'lib/src/app/conversation_workspace_slice/agent_conversation_workspace_store.dart',
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
