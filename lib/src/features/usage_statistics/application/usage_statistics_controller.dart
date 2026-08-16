import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/usage_statistics/domain/fallback_usage_statistics_text_catalog.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_report_builder.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart';

typedef UsageStatisticsClock = DateTime Function();

/// 使用统计页面的异步编排与筛选状态。
class UsageStatisticsController extends ChangeNotifier {
  UsageStatisticsController({
    required this.repository,
    UsageStatisticsClock? clock,
    UsageStatisticsTextCatalog? textCatalog,
  }) : _clock = clock ?? DateTime.now,
       _textCatalog = textCatalog ?? const FallbackUsageStatisticsTextCatalog();

  final UsageStatisticsRepository repository;
  final UsageStatisticsTextCatalog _textCatalog;
  final UsageStatisticsClock _clock;

  UsageTimeRangePreset _timePreset = UsageTimeRangePreset.last7Days;
  DateTime? _customStart;
  DateTime? _customEndInclusive;
  String? _projectPath;
  String? _providerId;
  String? _model;
  UsageRankSort _rankSort = UsageRankSort.calls;
  UsageStatisticsSourceSnapshot? _source;
  UsageStatisticsReport? _report;
  DateTime? _loadedEarliest;
  bool _loading = false;
  bool _initialized = false;
  bool _disposed = false;
  int _loadToken = 0;
  String? _errorMessage;

  UsageTimeRangePreset get timePreset => _timePreset;
  DateTime? get customStart => _customStart;
  DateTime? get customEndInclusive => _customEndInclusive;
  String? get projectPath => _projectPath;
  String? get providerId => _providerId;
  String? get model => _model;
  UsageRankSort get rankSort => _rankSort;
  UsageStatisticsReport? get report => _report;
  UsageStatisticsSourceSnapshot? get source => _source;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdated => _source?.refreshedAt;
  List<String> get warnings => _source?.warnings ?? const <String>[];

  UsageDateWindow get window => UsageDateWindow.resolve(
    preset: _timePreset,
    now: _clock(),
    customStart: _customStart,
    customEndInclusive: _customEndInclusive,
  );

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await _load(forceRefresh: false);
  }

  Future<void> refresh() => _load(forceRefresh: true);

  Future<void> selectTimePreset(UsageTimeRangePreset value) async {
    if (_timePreset == value) {
      return;
    }
    _timePreset = value;
    _rebuildReport();
    _notify();
    await _ensureWindowLoaded();
  }

  Future<void> selectCustomRange(DateTime start, DateTime endInclusive) async {
    _customStart = start;
    _customEndInclusive = endInclusive;
    _timePreset = UsageTimeRangePreset.custom;
    _rebuildReport();
    _notify();
    await _ensureWindowLoaded();
  }

  void selectProject(String? value) {
    if (_projectPath == value) {
      return;
    }
    _projectPath = value;
    _rebuildReport();
    _notify();
  }

  void selectProvider(String? value) {
    if (_providerId == value) {
      return;
    }
    _providerId = value;
    _rebuildReport();
    _notify();
  }

  void selectModel(String? value) {
    if (_model == value) {
      return;
    }
    _model = value;
    _rebuildReport();
    _notify();
  }

  void selectRankSort(UsageRankSort value) {
    if (_rankSort == value) {
      return;
    }
    _rankSort = value;
    _rebuildReport();
    _notify();
  }

  Future<void> _ensureWindowLoaded() async {
    final requiredEarliest = window.previous.start;
    final loadedEarliest = _loadedEarliest;
    if (loadedEarliest == null || requiredEarliest.isBefore(loadedEarliest)) {
      await _load(forceRefresh: false);
    }
  }

  Future<void> _load({required bool forceRefresh}) async {
    final token = ++_loadToken;
    final requiredEarliest = window.previous.start;
    _loading = true;
    _errorMessage = null;
    _notify();
    try {
      final source = await repository.load(
        earliest: requiredEarliest,
        forceRefresh: forceRefresh,
      );
      if (_disposed || token != _loadToken) {
        return;
      }
      _source = source;
      if (_loadedEarliest == null ||
          requiredEarliest.isBefore(_loadedEarliest!)) {
        _loadedEarliest = requiredEarliest;
      }
      _rebuildReport();
    } catch (error) {
      if (_disposed || token != _loadToken) {
        return;
      }
      _errorMessage = _textCatalog.loadFailed(error);
    } finally {
      if (!_disposed && token == _loadToken) {
        _loading = false;
        _notify();
      }
    }
  }

  void _rebuildReport() {
    final source = _source;
    if (source == null) {
      _report = null;
      return;
    }
    final nextReport = buildUsageStatisticsReport(
      source: source,
      window: window,
      filter: UsageStatisticsFilter(
        projectPath: _projectPath,
        providerId: _providerId,
        model: _model,
      ),
      // 主趋势图仅展示 Token 消耗。
      trendMetric: UsageTrendMetric.totalTokens,
      rankSort: _rankSort,
    );
    _projectPath = _retainOption(_projectPath, nextReport.projectOptions);
    _providerId = _retainOption(_providerId, nextReport.agentOptions);
    _model = _retainOption(_model, nextReport.modelOptions);
    _report = buildUsageStatisticsReport(
      source: source,
      window: window,
      filter: UsageStatisticsFilter(
        projectPath: _projectPath,
        providerId: _providerId,
        model: _model,
      ),
      trendMetric: UsageTrendMetric.totalTokens,
      rankSort: _rankSort,
    );
  }

  String? _retainOption(String? selected, List<String> options) {
    return selected == null || options.contains(selected) ? selected : null;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loadToken += 1;
    super.dispose();
  }
}
