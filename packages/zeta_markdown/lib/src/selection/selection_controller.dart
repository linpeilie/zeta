import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../clipboard/plain_text_serializer.dart';
import '../core/document.dart';
import 'structured_block_selection.dart';

class MarkdownSelectionController extends ChangeNotifier {
  MarkdownSelectionController({
    MarkdownPlainTextSerializer? serializer,
  }) : _serializer = serializer ?? const MarkdownPlainTextSerializer();

  final MarkdownPlainTextSerializer _serializer;

  MarkdownDocument _document = const MarkdownDocument.empty();
  DocumentSelection? _selection;
  final Map<int, _CachedSelectionBlockInfo> _blockInfoCache =
      <int, _CachedSelectionBlockInfo>{};
  MarkdownDocument? _boundsDocument;
  bool _boundsResolved = false;
  _SelectionDocumentBounds? _bounds;

  MarkdownDocument get document => _document;
  DocumentSelection? get selection => _selection;
  DocumentRange? get normalizedRange => _selection?.normalizedRange;
  bool get hasTextSelection => _selection != null;
  bool get hasSelection => hasTextSelection;

  String get selectedPlainText {
    final selection = _selection;
    if (selection == null) {
      return '';
    }
    return _serializer.serializeSelection(_document, selection);
  }

  void attachDocument(MarkdownDocument document) {
    if (!identical(_document, document)) {
      _document = document;
      _invalidateDocumentBounds();
      _blockInfoCache.removeWhere(
        (index, _) => index >= document.blocks.length,
      );
    }
    var changed = false;

    final selection = _selection;
    if (selection != null) {
      final clampedSelection = _clampSelection(selection);
      if (_selection != clampedSelection) {
        _selection = clampedSelection;
        changed = true;
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  void setSelection(DocumentSelection? selection) {
    final nextSelection = selection == null ? null : _clampSelection(selection);
    if (_selection == nextSelection) {
      return;
    }
    _selection = nextSelection;
    notifyListeners();
  }

  void clear() {
    if (_selection == null) {
      return;
    }
    _selection = null;
    notifyListeners();
  }

  void selectAll([MarkdownDocument? document]) {
    if (document != null) {
      _attachDocumentWithoutClamping(document);
    }
    final nextSelection = _createFullDocumentSelection();
    if (_selection == nextSelection) {
      return;
    }
    _selection = nextSelection;
    notifyListeners();
  }

  Future<void> copySelectionToClipboard() {
    if (!hasSelection) {
      return Future<void>.value();
    }
    return Clipboard.setData(ClipboardData(text: selectedPlainText));
  }

  bool get _canUseDefaultSerializerFastPath =>
      _serializer.runtimeType == MarkdownPlainTextSerializer;

  void _invalidateDocumentBounds() {
    _boundsDocument = null;
    _boundsResolved = false;
    _bounds = null;
  }

  void _attachDocumentWithoutClamping(MarkdownDocument document) {
    if (identical(_document, document)) {
      return;
    }
    _document = document;
    _invalidateDocumentBounds();
    _blockInfoCache.removeWhere(
      (index, _) => index >= document.blocks.length,
    );
  }

  DocumentSelection? _clampSelection(DocumentSelection selection) {
    if (!_canUseDefaultSerializerFastPath) {
      return _serializer.clampSelection(_document, selection);
    }
    final bounds = _resolveDocumentBounds();
    if (bounds == null) {
      return null;
    }
    return DocumentSelection(
      base: _clampPosition(bounds, selection.base),
      extent: _clampPosition(bounds, selection.extent),
    );
  }

  DocumentSelection? _createFullDocumentSelection() {
    if (!_canUseDefaultSerializerFastPath) {
      return _serializer.createFullDocumentSelection(_document);
    }
    final bounds = _resolveDocumentBounds();
    if (bounds == null) {
      return null;
    }
    final first = bounds.first;
    final last = bounds.last;
    return DocumentSelection(
      base: DocumentPosition(
        blockIndex: first.blockIndex,
        path: first.structure == null
            ? const PathInBlock(<int>[0])
            : first.structure!.startPosition(blockIndex: first.blockIndex).path,
        textOffset: 0,
      ),
      extent: DocumentPosition(
        blockIndex: last.blockIndex,
        path: last.structure == null
            ? const PathInBlock(<int>[0])
            : last.structure!.endPosition(blockIndex: last.blockIndex).path,
        textOffset: last.visibleTextLength,
      ),
    );
  }

  _SelectionDocumentBounds? _resolveDocumentBounds() {
    if (_boundsResolved && identical(_boundsDocument, _document)) {
      return _bounds;
    }

    _CachedSelectionBlockInfo? first;
    _CachedSelectionBlockInfo? last;
    for (var index = 0; index < _document.blocks.length; index++) {
      final info = _blockInfoFor(index);
      if (info.text.isEmpty) {
        continue;
      }
      first ??= info;
      last = info;
    }

    _boundsDocument = _document;
    _boundsResolved = true;
    _bounds = first == null || last == null
        ? null
        : _SelectionDocumentBounds(first: first, last: last);
    return _bounds;
  }

  _CachedSelectionBlockInfo _blockInfoFor(int blockIndex) {
    final block = _document.blocks[blockIndex];
    final cached = _blockInfoCache[blockIndex];
    if (cached != null && identical(cached.block, block)) {
      return cached;
    }

    final structure = StructuredBlockSelection.forBlock(block);
    final info = !structure.isEmpty
        ? _CachedSelectionBlockInfo(
            blockIndex: blockIndex,
            block: block,
            text: structure.serializedText,
            structure: structure,
          )
        : _CachedSelectionBlockInfo(
            blockIndex: blockIndex,
            block: block,
            text: StructuredBlockSelection.serializeBlockText(block),
            structure: null,
          );
    _blockInfoCache[blockIndex] = info;
    return info;
  }

  DocumentPosition _clampPosition(
    _SelectionDocumentBounds bounds,
    DocumentPosition position,
  ) {
    final minBlockIndex = bounds.first.blockIndex;
    final maxBlockIndex = bounds.last.blockIndex;
    final targetBlockIndex = position.blockIndex < minBlockIndex
        ? minBlockIndex
        : position.blockIndex > maxBlockIndex
            ? maxBlockIndex
            : position.blockIndex;
    final candidate = _blockInfoFor(targetBlockIndex);
    final block = candidate.text.isEmpty ? bounds.last : candidate;
    final targetOffset = position.textOffset < 0
        ? 0
        : position.textOffset > block.visibleTextLength
            ? block.visibleTextLength
            : position.textOffset;
    final structure = block.structure;
    if (structure != null) {
      return structure.normalizePosition(
        blockIndex: block.blockIndex,
        position: DocumentPosition(
          blockIndex: block.blockIndex,
          path: position.path,
          textOffset: targetOffset,
        ),
        affinity: targetOffset == structure.plainText.length
            ? StructuredSelectionAffinity.upstream
            : StructuredSelectionAffinity.downstream,
      );
    }
    return DocumentPosition(
      blockIndex: block.blockIndex,
      path: const PathInBlock(<int>[0]),
      textOffset: targetOffset,
    );
  }
}

class _SelectionDocumentBounds {
  const _SelectionDocumentBounds({
    required this.first,
    required this.last,
  });

  final _CachedSelectionBlockInfo first;
  final _CachedSelectionBlockInfo last;
}

class _CachedSelectionBlockInfo {
  const _CachedSelectionBlockInfo({
    required this.blockIndex,
    required this.block,
    required this.text,
    required this.structure,
  });

  final int blockIndex;
  final BlockNode block;
  final String text;
  final StructuredBlockSelection? structure;

  int get visibleTextLength => structure?.plainText.length ?? text.length;
}
