import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';

// WP-4: the runner is an effect executor, never another business owner.
const _synchronousMembers = <String>{
  'selectThread',
  'selectThreadId',
  'clearSelectedThread',
  'clearAllSelectedThreads',
  'registerThreadMapping',
  'registerSession',
  'setThreadRunning',
  'dismissCompletedThread',
  'syncRuntimeSnapshot',
  'effectiveListRuntimeStatus',
  'updateThreadTitle',
  'updateThreadPreview',
  'sessionSnapshot',
  'registerThreadSummaries',
  'registerStateThreadMappings',
};

List<String> _violations(String source) {
  final unit = parseString(content: source).unit;
  final runner = unit.declarations.whereType<ClassDeclaration>().singleWhere(
    (node) => node.namePart.typeName.lexeme == 'ProjectThreadsSliceRunner',
  );
  final violations = <String>[];
  for (final member in runner.body.members) {
    if (member is MethodDeclaration) {
      final name = member.name.lexeme;
      final normalized = name.startsWith('_') ? name.substring(1) : name;
      if (_synchronousMembers.contains(normalized) ||
          (!name.startsWith('_') && name != 'run' && name != 'close')) {
        violations.add(name);
      }
    } else if (member is FieldDeclaration) {
      final type = member.fields.type;
      final ownershipMap =
          type is NamedType &&
          type.name.lexeme == 'Map' &&
          type.typeArguments?.arguments
                  .map((arg) => arg.toSource())
                  .join(',') ==
              'String,String';
      for (final field in member.fields.variables) {
        if (ownershipMap || field.name.lexeme == '_projectPathByThreadId') {
          violations.add(field.name.lexeme);
        }
      }
    }
  }
  return violations;
}

void main() {
  test('production runner declares only effect execution and I/O resources', () {
    expect(
      _violations(
        File(
          'lib/src/app/project_threads_slice/project_threads_slice_runner.dart',
        ).readAsStringSync(),
      ),
      isEmpty,
    );
  });

  test('guard accepts private loaders, query reads and scheduling maps', () {
    expect(
      _violations('''
      class ProjectThreadsSliceRunner {
        final Map<String, int> _loadTokens = {};
        final Map<String, Timer> _timers = {};
        void run(Object effect) { _loadInitial(); }
        void close() {}
        void _loadInitial() {}
        Object _stateFor() => owner.stateFor('/repo');
        // registerSession and Map<String, String> in text are not members.
        String get _description => 'syncRuntimeSnapshot';
      }
    '''),
      isEmpty,
    );
  });

  test('guard rejects every deleted business method even when private', () {
    for (final name in _synchronousMembers) {
      for (final prefix in ['', '_']) {
        expect(
          _violations('''
          class ProjectThreadsSliceRunner { void $prefix$name() {} }
        '''),
          ['$prefix$name'],
        );
      }
    }
  });

  test(
    'guard rejects a second index even when renamed or split across lines',
    () {
      expect(
        _violations('''
      class ProjectThreadsSliceRunner {
        final Map<
          String, String
        > _renamedIndex = {};
        final _projectPathByThreadId = <String, String>{};
        Object get sessionSnapshot => null;
        void loadInitial() {}
      }
    '''),
        [
          '_renamedIndex',
          '_projectPathByThreadId',
          'sessionSnapshot',
          'loadInitial',
        ],
      );
    },
  );
}
