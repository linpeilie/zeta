import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

/// Agent Markdown 的有界解析与渲染保温缓存。
///
/// 控制器缓存避免历史消息重新进入视口时重复解析 Markdown；保温信号配合
/// Sliver 子项根节点的 `KeepAlive`，只让最近使用的少量重型渲染子树留在
/// keep-alive bucket 中，避免为全部历史消息永久保活。
final class AgentMarkdownCache {
  /// 创建缓存。
  AgentMarkdownCache({this.maxWarmEntries = 8, this.maxControllerEntries = 24})
    : assert(maxWarmEntries >= 0),
      assert(maxControllerEntries >= maxWarmEntries);

  /// 最多保留的 Markdown 渲染子树数量。
  final int maxWarmEntries;

  /// 最多保留的已解析 Markdown 控制器数量。
  final int maxControllerEntries;

  final LinkedHashMap<String, _AgentMarkdownCacheEntry> _entries =
      LinkedHashMap<String, _AgentMarkdownCacheEntry>();

  /// 当前请求保温的条目 id 集合（同步簿记）。
  ///
  /// `keepAlive` notifier 的写入被推迟到微任务，以避开 build 阶段通知监听者；
  /// 名额判定仍需要同步结果，因此单独维护此集合作为真源。
  final Set<String> _warmMessageIds = <String>{};

  bool _disposed = false;

  /// 诊断：新建并执行首次解析的控制器数量。
  int debugCreatedControllerCount = 0;

  /// 诊断：命中既有控制器的次数。
  int debugControllerHitCount = 0;

  /// 诊断：因容量或清理被释放的控制器数量。
  int debugDisposedControllerCount = 0;

  /// 当前缓存的控制器数量。
  int get controllerCount => _entries.length;

  /// 当前请求保活的渲染子树数量。
  int get warmEntryCount => _warmMessageIds.length;

  /// 获取指定消息的控制器租约。
  ///
  /// [preferIncrementalUpdate] 仅应给流式消息使用；当新文本是旧文本前缀追加时，
  /// 复用 Markdown 包的增量解析路径。
  AgentMarkdownCacheLease acquire({
    required String messageId,
    required String data,
    bool preferIncrementalUpdate = false,
  }) {
    final entry = _obtainEntry(
      messageId: messageId,
      data: data,
      preferIncrementalUpdate: preferIncrementalUpdate,
    );
    entry.referenceCount += 1;
    _trimControllerEntries();
    return AgentMarkdownCacheLease._(owner: this, entry: entry);
  }

  /// 在创建 Sliver child 前准备控制器，并返回根节点使用的保温信号。
  ///
  /// 根节点应通过普通 rebuild 将该值写入 `KeepAlive`，避免嵌套子树发送
  /// out-of-turn keep-alive ParentData 通知。
  ValueListenable<bool> prepareWarmEntry({
    required String messageId,
    required String data,
    bool preferIncrementalUpdate = false,
  }) {
    final entry = _obtainEntry(
      messageId: messageId,
      data: data,
      preferIncrementalUpdate: preferIncrementalUpdate,
    );
    // ValueListenableBuilder 尚未挂载时该 entry 还没有租约，不能在返回前淘汰。
    _trimControllerEntries(except: entry);
    return entry.keepAlive;
  }

  _AgentMarkdownCacheEntry _obtainEntry({
    required String messageId,
    required String data,
    required bool preferIncrementalUpdate,
  }) {
    if (_disposed) {
      throw StateError('AgentMarkdownCache 已释放。');
    }

    var entry = _entries.remove(messageId);
    if (entry == null) {
      entry = _AgentMarkdownCacheEntry(
        messageId: messageId,
        controller: MarkdownController(
          data: preferIncrementalUpdate ? '' : data,
        ),
      );
      debugCreatedControllerCount += 1;
      if (preferIncrementalUpdate) {
        _updateEntry(entry, data, preferIncrementalUpdate: true);
      }
    } else {
      debugControllerHitCount += 1;
      _updateEntry(
        entry,
        data,
        preferIncrementalUpdate: preferIncrementalUpdate,
      );
    }

    // remove + reinsert 将命中项移动到 LRU 尾部。
    _entries[messageId] = entry;
    _setKeepAlive(entry, true);
    _trimWarmEntries(except: entry);
    return entry;
  }

  void _updateEntry(
    _AgentMarkdownCacheEntry entry,
    String data, {
    required bool preferIncrementalUpdate,
  }) {
    final current = entry.controller.data;
    if (current == data) {
      return;
    }
    if (preferIncrementalUpdate && data.startsWith(current)) {
      entry.controller.appendChunk(data.substring(current.length));
      return;
    }
    entry.controller.setData(data);
  }

  void _touch(_AgentMarkdownCacheEntry entry) {
    if (_disposed || !_entries.containsKey(entry.messageId)) {
      return;
    }
    _entries.remove(entry.messageId);
    _entries[entry.messageId] = entry;
    _setKeepAlive(entry, true);
    _trimWarmEntries(except: entry);
  }

  void _trimWarmEntries({_AgentMarkdownCacheEntry? except}) {
    var warmCount = warmEntryCount;
    if (warmCount <= maxWarmEntries) {
      return;
    }
    for (final candidate in _entries.values) {
      if (warmCount <= maxWarmEntries) {
        break;
      }
      if (identical(candidate, except) ||
          !_warmMessageIds.contains(candidate.messageId)) {
        continue;
      }
      _setKeepAlive(candidate, false);
      warmCount -= 1;
    }
    if (warmCount > maxWarmEntries &&
        except != null &&
        _warmMessageIds.contains(except.messageId)) {
      _setKeepAlive(except, false);
    }
  }

  /// 更新保温簿记，并把 notifier 写入推迟到微任务。
  ///
  /// `acquire`/`prepareWarmEntry` 会在 Sliver 的 build 阶段被调用；此时同步写入
  /// 会通知到正处于重建/卸载中的 `ValueListenableBuilder`（DEFUNCT element），
  /// 触发 “markNeedsBuild during build” 断言。保温信号只影响 keep-alive 名额，
  /// 允许最终一致，因此簿记同步更新、通知统一推迟。
  void _setKeepAlive(_AgentMarkdownCacheEntry entry, bool value) {
    final messageId = entry.messageId;
    if (value) {
      _warmMessageIds.add(messageId);
    } else {
      _warmMessageIds.remove(messageId);
    }
    final notifier = entry.keepAlive;
    scheduleMicrotask(() {
      if (!entry.disposed && notifier.value != value) {
        notifier.value = value;
      }
    });
  }

  void _release(_AgentMarkdownCacheEntry entry) {
    if (entry.disposed) {
      return;
    }
    if (entry.referenceCount > 0) {
      entry.referenceCount -= 1;
    }
    if (entry.referenceCount == 0) {
      // 没有渲染子树时无需占用 warm 配额；解析结果仍可留在控制器 LRU 中。
      _setKeepAlive(entry, false);
    }
    _trimControllerEntries();
  }

  void _trimControllerEntries({_AgentMarkdownCacheEntry? except}) {
    while (_entries.length > maxControllerEntries) {
      String? evictionKey;
      for (final candidate in _entries.entries) {
        if (!identical(candidate.value, except) &&
            candidate.value.referenceCount == 0) {
          evictionKey = candidate.key;
          break;
        }
      }
      if (evictionKey == null) {
        return;
      }
      final evicted = _entries.remove(evictionKey)!;
      _disposeEntry(evicted);
    }
  }

  void _disposeEntry(_AgentMarkdownCacheEntry entry) {
    if (entry.disposed) {
      return;
    }
    entry.disposed = true;
    _setKeepAlive(entry, false);
    entry
      ..keepAlive.dispose()
      ..controller.dispose();
    debugDisposedControllerCount += 1;
  }

  /// 清空全部解析结果。
  void clear() {
    final entries = _entries.values.toList(growable: false);
    _entries.clear();
    for (final entry in entries) {
      _disposeEntry(entry);
    }
  }

  /// 释放缓存。
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    clear();
  }
}

/// 单个 Markdown 控制器及其渲染保温信号的租约。
final class AgentMarkdownCacheLease {
  AgentMarkdownCacheLease._({required this._owner, required this._entry});

  final AgentMarkdownCache _owner;
  final _AgentMarkdownCacheEntry _entry;
  bool _released = false;

  /// 当前消息的 Markdown 控制器。
  MarkdownController get controller => _entry.controller;

  /// Sliver 是否应继续保留当前 Markdown 渲染子树。
  bool get shouldKeepAlive => _entry.keepAlive.value;

  /// 保活信号；变化时调用方应执行 `updateKeepAlive()`。
  ValueListenable<bool> get keepAliveListenable => _entry.keepAlive;

  /// 更新消息文本，并刷新 LRU 热度。
  void updateData(String data, {bool preferIncrementalUpdate = false}) {
    if (_released) {
      return;
    }
    _owner
      .._updateEntry(
        _entry,
        data,
        preferIncrementalUpdate: preferIncrementalUpdate,
      )
      .._touch(_entry);
  }

  /// 释放当前渲染子树持有的租约。
  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _owner._release(_entry);
  }
}

final class _AgentMarkdownCacheEntry {
  _AgentMarkdownCacheEntry({required this.messageId, required this.controller});

  final String messageId;
  final MarkdownController controller;
  final ValueNotifier<bool> keepAlive = ValueNotifier<bool>(false);
  int referenceCount = 0;
  bool disposed = false;
}
