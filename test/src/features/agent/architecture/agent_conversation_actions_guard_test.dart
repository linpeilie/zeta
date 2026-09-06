import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = 'lib/src/features/agent/application/conversation_slice/';
CompilationUnit _parse(String source) => parseString(content: source).unit;
String _read(String name) => File('$_base$name.dart').readAsStringSync();
void main() {
  test(
    'UI write calls and tear-offs use captured Actions, including aliases',
    () {
      final actionsSource = _read('agent_conversation_actions');
      final actions = _parse(actionsSource).declarations
          .whereType<ClassDeclaration>()
          .firstWhere(
            (c) => c.namePart.typeName.lexeme == 'AgentConversationActions',
          );
      final methods = actions.body.members
          .whereType<MethodDeclaration>()
          .map((m) => m.name.lexeme)
          .toSet();
      expect(methods, hasLength(35));
      final files = Directory('lib/src/features/agent/presentation')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty);
      for (final file in files) {
        expect(
          _uiViolations(file.readAsStringSync(), methods),
          isEmpty,
          reason: file.path,
        );
      }
      final types = _ForbiddenTypes({
        'AgentConversationCommandPort',
        'AgentConversationRuntimeController',
        'WidgetRef',
      });
      _parse(actionsSource).accept(types);
      expect(types.found, isEmpty);
      final provider = _parse(actionsSource).declarations
          .whereType<TopLevelVariableDeclaration>()
          .expand((d) => d.variables.variables)
          .singleWhere(
            (v) => v.name.lexeme == 'agentConversationActionsProvider',
          );
      final calls = _Calls();
      provider.accept(calls);
      expect(
        calls.names,
        containsAll([
          'agentConversationOwnerResolutionProvider',
          'agentConversationSliceOwnerProvider',
        ]),
      );
      expect(calls.names, isNot(contains('agentConversationRuntimeProvider')));
      final render = _parse(
        File(
          'lib/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer.dart',
        ).readAsStringSync(),
      );
      expect(
        _fields(render, 'AgentTimelineRenderContext'),
        containsPair('actions', 'AgentConversationActions'),
      );
      expect(
        _fields(render, 'AgentTimelineRenderContext'),
        containsPair('bindingKey', 'AgentConversationBindingKey'),
      );
    },
  );
  test(
    'runner validates both lifetime and scope before execution and commit',
    () {
      final source = _read('agent_conversation_command_effect_runner');
      final calls = _methodCalls(source, '_runAsync');
      final execute = calls.indexOf('_canExecute'),
          invoke = calls.indexOf('_invokeAsync'),
          commit = calls.indexOf('_canCommit');
      expect(execute, isNonNegative);
      expect(invoke, greaterThan(execute));
      expect(commit, greaterThan(invoke));
      expect(
        _methodCalls(source, '_canExecute'),
        containsAll(['isOpenOperation', 'matchesForExecution']),
      );
      expect(
        _methodCalls(source, '_canCommit'),
        containsAll(['isOpenOperation', 'matchesForCommit']),
      );
      final visitor = _ForbiddenTypes({
        'Ref',
        'WidgetRef',
        'AgentConversationSliceNotifier',
        'AgentConversationRuntimeController',
      });
      _parse(source).accept(visitor);
      expect(visitor.found, isEmpty);
      expect(
        _fields(
          _parse(_read('agent_conversation_command_payload')),
          'AgentConversationCommandEnvelope',
        ),
        containsPair('ownerLifetimeToken', 'Object'),
      );
    },
  );
  test('negative fixtures reject bypasses and runner owner access', () {
    const methods = {'sendMessage', 'respondToQuestion', 'toggleToolCall'};
    for (final source in [
      'void f() { controller.sendMessage("x"); }',
      'void f() { final callback = widget.controller.respondToQuestion; }',
      'void f() { final alias = runtime; alias.toggleToolCall("x"); }',
      'void f() { final first = viewModel; final second = first; final callback = second.sendMessage; }',
    ]) {
      expect(_uiViolations(source, methods), isNotEmpty);
    }
    expect(
      _uiViolations(
        'void f() { final captured = actions.sendMessage; actions.toggleToolCall("x"); final state = controller.headerState; }',
        methods,
      ),
      isEmpty,
    );
    final visitor = _ForbiddenTypes({'Ref'});
    _parse('class Runner { final Ref ref; Runner(this.ref); }').accept(visitor);
    expect(visitor.found, ['Ref']);
    expect(
      _methodCalls(
        'class Runner { void _runAsync() { _invokeAsync(); _canCommit(); } }',
        '_runAsync',
      ),
      isNot(contains('_canExecute')),
    );
  });
}

Map<String, String> _fields(CompilationUnit unit, String name) {
  final type = unit.declarations.whereType<ClassDeclaration>().singleWhere(
    (c) => c.namePart.typeName.lexeme == name,
  );
  return {
    for (final field in type.body.members.whereType<FieldDeclaration>())
      for (final variable in field.fields.variables)
        variable.name.lexeme: field.fields.type!.toSource(),
  };
}

List<String> _methodCalls(String source, String name) {
  final method = _parse(source).declarations
      .whereType<ClassDeclaration>()
      .expand((c) => c.body.members)
      .whereType<MethodDeclaration>()
      .singleWhere((m) => m.name.lexeme == name);
  final calls = _Calls();
  method.accept(calls);
  return calls.names;
}

class _Calls extends RecursiveAstVisitor<void> {
  final names = <String>[];
  @override
  void visitMethodInvocation(MethodInvocation node) {
    names.add(node.methodName.name);
    super.visitMethodInvocation(node);
  }
}

class _ForbiddenTypes extends RecursiveAstVisitor<void> {
  _ForbiddenTypes(this.banned);
  final Set<String> banned;
  final found = <String>[];
  @override
  void visitNamedType(NamedType node) {
    if (banned.contains(node.name.lexeme)) found.add(node.name.lexeme);
    super.visitNamedType(node);
  }
}

List<String> _uiViolations(String source, Set<String> methods) {
  final visitor = _UiWrites(methods);
  _parse(source).accept(visitor);
  return visitor.found;
}

class _UiWrites extends RecursiveAstVisitor<void> {
  _UiWrites(this.methods);
  final Set<String> methods;
  final aliases = {'controller', 'runtime', '_runtime', 'viewModel'};
  final found = <String>[];
  bool isRuntime(AstNode? target) =>
      target != null &&
      RegExp(
        r'[A-Za-z_]\w*',
      ).allMatches(target.toSource()).any((m) => aliases.contains(m[0]));
  void check(AstNode? target, String name) {
    if (methods.contains(name) && isRuntime(target)) found.add(name);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (isRuntime(node.initializer)) aliases.add(node.name.lexeme);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    check(node.target, node.methodName.name);
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    check(node.target, node.propertyName.name);
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    check(node.prefix, node.identifier.name);
    super.visitPrefixedIdentifier(node);
  }
}
