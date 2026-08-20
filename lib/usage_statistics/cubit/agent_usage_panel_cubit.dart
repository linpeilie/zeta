import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';

export 'package:usage_statistics_repository/usage_statistics_repository.dart'
    show UsageQuotaResult;

enum AgentUsagePanelTab { summary, quota }

enum AgentUsagePanelStatus { initial, loading, ready, failure }

final class AgentUsagePanelState extends Equatable {
  const AgentUsagePanelState({
    this.status = AgentUsagePanelStatus.initial,
    this.tab = AgentUsagePanelTab.summary,
    this.quotaResults = const <UsageQuotaResult>[],
  });

  final AgentUsagePanelStatus status;
  final AgentUsagePanelTab tab;
  final List<UsageQuotaResult> quotaResults;

  AgentUsagePanelState copyWith({
    AgentUsagePanelStatus? status,
    AgentUsagePanelTab? tab,
    List<UsageQuotaResult>? quotaResults,
  }) {
    return AgentUsagePanelState(
      status: status ?? this.status,
      tab: tab ?? this.tab,
      quotaResults: quotaResults ?? this.quotaResults,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, tab, quotaResults];
}

// Named public constructor parameters initialize private fields.
// ignore_for_file: prefer_initializing_formals

class AgentUsagePanelCubit extends Cubit<AgentUsagePanelState> {
  AgentUsagePanelCubit({
    required UsageStatisticsRepository usageStatisticsRepository,
  }) : _usageStatisticsRepository = usageStatisticsRepository,
       super(const AgentUsagePanelState());

  final UsageStatisticsRepository _usageStatisticsRepository;
  var _quotaLoadInFlight = false;

  void selectTab(AgentUsagePanelTab tab) {
    if (isClosed) {
      return;
    }
    emit(state.copyWith(tab: tab));
    if (tab == AgentUsagePanelTab.quota &&
        state.quotaResults.isEmpty &&
        !_quotaLoadInFlight) {
      unawaited(loadQuota());
    }
  }

  Future<void> loadQuota() async {
    if (isClosed || _quotaLoadInFlight) {
      return;
    }
    _quotaLoadInFlight = true;
    emit(state.copyWith(status: AgentUsagePanelStatus.loading));
    try {
      final results = await _usageStatisticsRepository.quotaSnapshots();
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          status: AgentUsagePanelStatus.ready,
          quotaResults: results,
        ),
      );
    } on Object {
      if (isClosed) {
        return;
      }
      emit(state.copyWith(status: AgentUsagePanelStatus.failure));
    } finally {
      _quotaLoadInFlight = false;
    }
  }
}
