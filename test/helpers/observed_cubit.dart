import 'package:bloc/bloc.dart';

/// Minimal cubit used to drive [BlocObserver] callbacks in tests.
class ObservedCubit extends Cubit<int> {
  /// Creates a cubit seeded with zero.
  ObservedCubit() : super(0);
}
