import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/agent_file_change_projection.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';

void main() {
  group('buildAgentTimelineRenderBlocks', () {
    test('groups consecutive non-edit operations into a command group', () {
      final blocks = buildAgentTimelineRenderBlocks(
        turnId: 'turn-a',
        entries: <AgentTimelineEntry>[
          _toolEntry(
            id: 'tool-1',
            kind: AgentToolKind.execute,
            title: 'Run tests',
            content: 'flutter test\nhidden line',
          ),
          _searchEntry(
            id: 'search-1',
            title: 'Web search',
            description: 'OpenAI docs',
            content: 'OpenAI docs\nHidden result',
          ),
          _messageEntry(id: 'message-1', text: 'Done'),
        ],
      );

      expect(blocks, hasLength(2));
      expect(blocks.first, isA<AgentTimelineCommandGroupRenderBlock>());

      final group = blocks.first as AgentTimelineCommandGroupRenderBlock;
      expect(group.group.id, 'command-group-turn-a-tool-tool-1');
      expect(group.group.items, hasLength(2));
      expect(group.group.items[0].title, 'Run tests');
      expect(group.group.items[1].title, 'Web search · OpenAI docs');
      expect(blocks.last, isA<AgentTimelineEntryRenderBlock>());
    });

    test('groups a single non-edit operation into a command group', () {
      final blocks = buildAgentTimelineRenderBlocks(
        turnId: 'turn-a',
        entries: <AgentTimelineEntry>[
          _toolEntry(
            id: 'tool-1',
            kind: AgentToolKind.execute,
            title: 'Run tests',
            content: 'flutter test',
          ),
        ],
      );

      expect(blocks, hasLength(1));
      expect(blocks.single, isA<AgentTimelineCommandGroupRenderBlock>());
      final single = blocks.single as AgentTimelineCommandGroupRenderBlock;
      expect(single.group.id, 'command-group-turn-a-tool-tool-1');
      expect(single.group.items.single.title, 'Run tests');
    });

    test('skips reasoning without splitting visible command groups', () {
      final blocks = buildAgentTimelineRenderBlocks(
        turnId: 'turn-a',
        entries: <AgentTimelineEntry>[
          _toolEntry(
            id: 'tool-1',
            kind: AgentToolKind.execute,
            title: 'Run tests',
          ),
          _toolEntry(
            id: 'reasoning-1',
            kind: AgentToolKind.think,
            title: '思考',
            content: 'private reasoning summary',
          ),
          _toolEntry(
            id: 'tool-2',
            kind: AgentToolKind.read,
            title: 'Read result',
          ),
        ],
      );

      expect(blocks, hasLength(1));
      final group = blocks.single as AgentTimelineCommandGroupRenderBlock;
      expect(group.group.items.map((item) => item.id), <String>[
        'tool-tool-1',
        'tool-tool-2',
      ]);
    });

    test('creates a file edit group for a single edit tool', () {
      final blocks = buildAgentTimelineRenderBlocks(
        turnId: 'turn-a',
        entries: <AgentTimelineEntry>[
          _toolEntry(
            id: 'edit-1',
            kind: AgentToolKind.edit,
            title: 'Apply patch',
            fileChanges: _snapshot(<AgentFileChange>[
              const AgentFileChange(
                id: 'main-change',
                path: 'lib/main.dart',
                kind: AgentFileChangeKind.modified,
                evidence: AgentUnifiedPatchEvidence(
                  patch: '@@ -1 +1 @@\n-old line\n+new line\n',
                ),
              ),
            ]),
          ),
        ],
      );

      expect(blocks, hasLength(1));
      expect(blocks.single, isA<AgentTimelineFileEditGroupRenderBlock>());
      final group = blocks.single as AgentTimelineFileEditGroupRenderBlock;
      expect(group.group.id, 'file-edit-group-turn-a-tool-edit-1');
      expect(group.group.items, hasLength(1));
      expect(group.group.items.single.title, 'main.dart');
      expect(group.group.items.single.addedLines, 1);
      expect(group.group.items.single.removedLines, 1);
      expect(group.group.items.single.hasDetails, isTrue);
      expect(
        group.group.items.single.projection.detail,
        isA<AgentUnifiedPatchDetailProjection>().having(
          (detail) => detail.lines.first.text,
          'first line',
          '@@ -1 +1 @@',
        ),
      );
    });

    test('splits a multi-file patch into file-level edit items', () {
      final blocks = buildAgentTimelineRenderBlocks(
        turnId: 'turn-a',
        entries: <AgentTimelineEntry>[
          _toolEntry(
            id: 'edit-1',
            kind: AgentToolKind.edit,
            title: 'Apply patch',
            fileChanges: _snapshot(<AgentFileChange>[
              const AgentFileChange(
                id: 'main-change',
                path: 'lib/main.dart',
                kind: AgentFileChangeKind.modified,
                evidence: AgentUnifiedPatchEvidence(
                  patch: '@@ -1 +1 @@\n-old line\n+new line\n',
                ),
              ),
              const AgentFileChange(
                id: 'readme-change',
                path: 'README.md',
                kind: AgentFileChangeKind.modified,
                evidence: AgentUnifiedPatchEvidence(
                  patch: '@@ -0,0 +1 @@\n+docs line\n',
                ),
              ),
            ]),
          ),
        ],
      );

      final group = blocks.single as AgentTimelineFileEditGroupRenderBlock;
      expect(group.group.items, hasLength(2));
      expect(group.group.items[0].title, 'main.dart');
      expect(group.group.items[0].addedLines, 1);
      expect(group.group.items[0].removedLines, 1);
      expect(group.group.items[1].title, 'README.md');
      expect(group.group.items[1].addedLines, 1);
      expect(group.group.items[1].removedLines, 0);
      final mainDetail = group.group.items[0].projection.detail;
      final readmeDetail = group.group.items[1].projection.detail;
      expect(
        mainDetail,
        isA<AgentUnifiedPatchDetailProjection>().having(
          (detail) => detail.lines.map((line) => line.text),
          'lines',
          contains('+new line'),
        ),
      );
      expect(
        readmeDetail,
        isA<AgentUnifiedPatchDetailProjection>().having(
          (detail) => detail.lines.map((line) => line.text),
          'lines',
          contains('+docs line'),
        ),
      );
    });

    test('keeps file edits separate from command groups', () {
      final blocks = buildAgentTimelineRenderBlocks(
        turnId: 'turn-a',
        entries: <AgentTimelineEntry>[
          _toolEntry(
            id: 'edit-1',
            kind: AgentToolKind.edit,
            title: 'Apply patch',
            fileChanges: _snapshot(<AgentFileChange>[
              const AgentFileChange(
                id: 'main-change',
                path: 'lib/main.dart',
                kind: AgentFileChangeKind.modified,
                evidence: AgentUnifiedPatchEvidence(
                  patch: '@@ -0,0 +1 @@\n+new line\n',
                ),
              ),
            ]),
          ),
          _toolEntry(
            id: 'edit-2',
            kind: AgentToolKind.edit,
            title: 'Apply patch',
            fileChanges: _snapshot(<AgentFileChange>[
              const AgentFileChange(
                id: 'readme-change',
                path: 'README.md',
                kind: AgentFileChangeKind.modified,
                evidence: AgentUnifiedPatchEvidence(
                  patch: '@@ -0,0 +1 @@\n+docs line\n',
                ),
              ),
            ]),
          ),
          _toolEntry(
            id: 'tool-3',
            kind: AgentToolKind.execute,
            title: 'Run tests',
          ),
          _searchEntry(
            id: 'search-1',
            title: 'Tool search',
            description: 'rip_grep_packages',
          ),
        ],
      );

      expect(blocks, hasLength(2));
      expect(blocks.first, isA<AgentTimelineFileEditGroupRenderBlock>());
      expect(blocks.last, isA<AgentTimelineCommandGroupRenderBlock>());
      final editGroup = blocks.first as AgentTimelineFileEditGroupRenderBlock;
      final commandGroup = blocks.last as AgentTimelineCommandGroupRenderBlock;
      expect(editGroup.group.items, hasLength(2));
      expect(commandGroup.group.items.map((item) => item.title), <String>[
        'Run tests',
        'Tool search',
      ]);
    });

    test('keeps tools without typed snapshots in the command group', () {
      final blocks = buildAgentTimelineRenderBlocks(
        turnId: 'turn-a',
        entries: <AgentTimelineEntry>[
          _toolEntry(
            id: 'tool-delete',
            kind: AgentToolKind.delete,
            title: 'Delete file',
          ),
          _toolEntry(
            id: 'tool-move',
            kind: AgentToolKind.move,
            title: 'Move file',
          ),
        ],
      );

      expect(blocks, hasLength(1));
      expect(blocks.single, isA<AgentTimelineCommandGroupRenderBlock>());
      final group = blocks.single as AgentTimelineCommandGroupRenderBlock;
      expect(group.group.items.map((item) => item.kind), <AgentToolKind>[
        AgentToolKind.delete,
        AgentToolKind.move,
      ]);
    });

    test('uses typed snapshot presence instead of tool kind for grouping', () {
      final blocks = buildAgentTimelineRenderBlocks(
        turnId: 'turn-a',
        entries: <AgentTimelineEntry>[
          _toolEntry(
            id: 'tool-move',
            kind: AgentToolKind.move,
            title: 'Move file',
            fileChanges: _snapshot(<AgentFileChange>[
              const AgentFileChange(
                id: 'move-change',
                path: 'lib/old.dart',
                destinationPath: 'lib/new.dart',
                kind: AgentFileChangeKind.moved,
              ),
            ]),
          ),
        ],
      );

      final group = blocks.single as AgentTimelineFileEditGroupRenderBlock;
      expect(group.group.items.single.filePath, 'lib/old.dart');
      expect(
        group.group.items.single.projection.destinationPath,
        'lib/new.dart',
      );
    });

    test(
      'shows file names without line stats when patch details are unavailable',
      () {
        final blocks = buildAgentTimelineRenderBlocks(
          turnId: 'turn-a',
          entries: <AgentTimelineEntry>[
            _toolEntry(
              id: 'edit-1',
              kind: AgentToolKind.edit,
              title: 'File change',
              fileChanges: _snapshot(<AgentFileChange>[
                const AgentFileChange(
                  id: 'main-change',
                  path: 'lib/main.dart',
                  kind: AgentFileChangeKind.modified,
                ),
              ]),
            ),
          ],
        );

        final group = blocks.single as AgentTimelineFileEditGroupRenderBlock;
        expect(group.group.items, hasLength(1));
        expect(group.group.items.single.title, 'main.dart');
        expect(group.group.items.single.addedLines, isNull);
        expect(group.group.items.single.removedLines, isNull);
        expect(group.group.items.single.hasDetails, isFalse);
      },
    );

    test('does not create file edits from legacy raw payloads', () {
      final blocks = buildAgentTimelineRenderBlocks(
        turnId: 'turn-a',
        entries: <AgentTimelineEntry>[
          _toolEntry(
            id: 'edit-legacy',
            kind: AgentToolKind.edit,
            title: 'Apply patch',
            rawInput: <String, Object?>{
              'input':
                  '*** Begin Patch\n'
                  '*** Update File: lib/main.dart\n'
                  '@@\n'
                  '-old line\n'
                  '+new line\n'
                  '*** End Patch\n',
            },
            rawOutput: const <String, Object?>{
              'changes': <String, Object?>{
                'lib/main.dart': <String, Object?>{'type': 'update'},
              },
            },
          ),
        ],
      );

      final group = blocks.single as AgentTimelineCommandGroupRenderBlock;
      expect(group.group.items.single.title, 'Apply patch');
    });

    test('renders typed turn-level changes without parsing patch headers', () {
      final blocks = buildAgentTimelineRenderBlocks(
        turnId: 'turn-a',
        entries: <AgentTimelineEntry>[
          AgentTurnFileChangesTimelineEntry(
            turnId: 'turn-a',
            snapshot: AgentFileChangeSnapshot(
              revision: 1,
              replayability: AgentFileChangeReplayability.liveOnly,
              changes: const <AgentFileChange>[
                AgentFileChange(
                  id: 'change-a',
                  path: 'lib/a.dart',
                  kind: AgentFileChangeKind.modified,
                  evidence: AgentUnifiedPatchEvidence(
                    patch: '@@ -1 +1 @@\n-old\n+new\n',
                  ),
                ),
                AgentFileChange(
                  id: 'change-b',
                  path: 'lib/b.dart',
                  kind: AgentFileChangeKind.modified,
                  evidence: AgentUnifiedPatchEvidence(
                    patch: '@@ -1 +1,2 @@\n keep\n+added\n',
                  ),
                ),
              ],
            ),
          ),
        ],
      );

      expect(blocks, hasLength(1));
      expect(blocks.single, isA<AgentTimelineFileEditGroupRenderBlock>());
      final group = blocks.single as AgentTimelineFileEditGroupRenderBlock;
      expect(group.group.id, 'turn-file-changes-group-turn-a');
      expect(group.group.isTurnFallback, isTrue);
      expect(group.group.items, hasLength(2));
      expect(group.group.items[0].title, 'a.dart');
      expect(group.group.items[0].addedLines, 1);
      expect(group.group.items[0].removedLines, 1);
      expect(group.group.items[0].hasDetails, isTrue);
      expect(group.group.items[1].title, 'b.dart');
      expect(group.group.items[1].addedLines, 1);
      expect(group.group.items[1].removedLines, 0);
    });

    test('skips web search entries that do not contain a concrete query', () {
      final blocks = buildAgentTimelineRenderBlocks(
        turnId: 'turn-a',
        entries: <AgentTimelineEntry>[
          _toolEntry(
            id: 'tool-1',
            kind: AgentToolKind.execute,
            title: 'Run tests',
          ),
          _searchEntry(id: 'search-empty', title: 'Web search'),
          _toolEntry(
            id: 'tool-2',
            kind: AgentToolKind.read,
            title: 'Read file',
          ),
        ],
      );

      expect(blocks, hasLength(1));
      final group = blocks.single as AgentTimelineCommandGroupRenderBlock;
      expect(group.group.items.map((item) => item.title), <String>[
        'Run tests',
        'Read file',
      ]);
    });

    test('dedupes entries that share the same timeline id', () {
      final blocks = buildAgentTimelineRenderBlocks(
        turnId: 'turn-a',
        entries: <AgentTimelineEntry>[
          _messageEntry(id: 'error-same', text: 'first'),
          _messageEntry(id: 'error-same', text: 'second'),
        ],
      );

      expect(blocks, hasLength(1));
      final block = blocks.single as AgentTimelineEntryRenderBlock;
      expect(block.id, 'message-error-same');
      final entry = block.entry as AgentMessageTimelineEntry;
      expect(entry.message.text, 'first');
    });
  });
}

AgentToolTimelineEntry _toolEntry({
  required String id,
  required AgentToolKind kind,
  required String title,
  String? content,
  List<String> locations = const <String>[],
  Map<String, Object?> rawInput = const <String, Object?>{},
  Map<String, Object?> rawOutput = const <String, Object?>{},
  Map<String, Object?> raw = const <String, Object?>{},
  AgentFileChangeSnapshot? fileChanges,
}) {
  return AgentToolTimelineEntry(
    toolCall: AgentToolCall(
      id: id,
      title: title,
      kind: kind,
      status: AgentToolStatus.completed,
      content: content,
      locations: locations,
      rawInput: rawInput,
      rawOutput: rawOutput,
      raw: raw,
      fileChanges: fileChanges,
    ),
  );
}

AgentHistoryEventTimelineEntry _searchEntry({
  required String id,
  required String title,
  String? description,
  String? content,
}) {
  return AgentHistoryEventTimelineEntry(
    event: AgentHistoryEventEntry(
      id: id,
      kind: AgentHistoryEventKind.search,
      title: title,
      description: description,
      content: content,
    ),
  );
}

AgentMessageTimelineEntry _messageEntry({
  required String id,
  required String text,
}) {
  return AgentMessageTimelineEntry(
    message: AgentConversationMessage(
      id: id,
      role: AgentMessageRole.agent,
      text: text,
    ),
  );
}

AgentFileChangeSnapshot _snapshot(List<AgentFileChange> changes) {
  return AgentFileChangeSnapshot(
    revision: 1,
    replayability: AgentFileChangeReplayability.replayable,
    changes: changes,
  );
}
