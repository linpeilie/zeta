import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _application = 'lib/src/features/agent_management/application';

final class _DetectionBoundary extends RecursiveAstVisitor<void> {
  final violations = <String>[];
  @override
  void visitNamedType(NamedType node) {
    if ([
      'ManagedAgent',
      'AgentDefinition',
      'AgentConnectionTestResult',
      'WidgetRef',
      'BuildContext',
      'Locale',
    ].contains(node.name.lexeme)) {
      violations.add(node.name.lexeme);
    }
    super.visitNamedType(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if ([
      'executablePath',
      'configPath',
      'logPaths',
      'rawErrorSummary',
      'errorDetails',
    ].contains(node.name.lexeme)) {
      violations.add(node.name.lexeme);
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitImportDirective(ImportDirective node) {
    final uri = node.uri.stringValue ?? '';
    if (uri.startsWith('dart:io') ||
        uri.startsWith('package:flutter/') ||
        uri.contains('/presentation/')) {
      violations.add(uri);
    }
  }
}

List<String> _violations(String source) {
  final visitor = _DetectionBoundary();
  parseString(content: source).unit.accept(visitor);
  return visitor.violations;
}

void main() {
  test('management application accepts only safe detection models', () {
    for (final file
        in Directory(_application)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      expect(_violations(file.readAsStringSync()), isEmpty, reason: file.path);
    }
    final state = parseString(
      content: File(
        '$_application/agent_management_slice/agent_management_slice_state.dart',
      ).readAsStringSync(),
    ).unit;
    final cls = state.declarations.whereType<ClassDeclaration>().singleWhere(
      (c) => c.namePart.typeName.lexeme == 'AgentManagementSliceState',
    );
    final fields = cls.body.members
        .whereType<FieldDeclaration>()
        .expand((f) => f.fields.variables)
        .map((v) => v.name.lexeme);
    expect(fields, isNot(contains('agentsById')));
  });
  test('home has no private detector or rollback cache', () {
    final home = File(
      'lib/src/ui/features/ide/views/ide_home.dart',
    ).readAsStringSync();
    for (final name in [
      '_installedHomeProviders',
      '_homeProvidersLoading',
      '_homeProviderError',
      '_globalHomeLoadToken',
      '_loadHomeProviders',
      '_handleAgentManagementChanged',
      '_agentManagementHomeRefreshScheduled',
    ]) {
      expect(home, isNot(contains(name)));
    }
    final production = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in production) {
      expect(
        file.readAsStringSync(),
        isNot(contains('HomeProviderDetectionLoader')),
        reason: file.path,
      );
    }
  });
  test('guard rejects unsafe paths and raw repository aggregates', () {
    expect(
      _violations(
        "import 'dart:io'; class X { final ManagedAgent a; final AgentDefinition b; final AgentConnectionTestResult c; final String executablePath; final String rawErrorSummary; }",
      ),
      hasLength(6),
    );
    expect(
      _violations(
        'class X { final AgentManagementDetailsHandle? handle; final bool executableLocated; final int availableLogFileCount; }',
      ),
      isEmpty,
    );
  });
}
