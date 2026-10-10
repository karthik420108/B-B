import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

class ScheduledDose {
  final String id;
  final String medicationName;
  final String strength;
  final String instructions;
  final DateTime scheduledTime;
  final bool isTaken;

  ScheduledDose({
    required this.id,
    required this.medicationName,
    required this.strength,
    required this.instructions,
    required this.scheduledTime,
    this.isTaken = false,
  });

  ScheduledDose copyWith({bool? isTaken}) {
    return ScheduledDose(
      id: id,
      medicationName: medicationName,
      strength: strength,
      instructions: instructions,
      scheduledTime: scheduledTime,
      isTaken: isTaken ?? this.isTaken,
    );
  }
}

class ScheduleNotifier extends StateNotifier<AsyncValue<List<ScheduledDose>>> {
  ScheduleNotifier() : super(const AsyncValue.loading()) {
    _loadMockData();
  }

  Future<void> _loadMockData() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));
    final now = DateTime.now();
    
    // Mock schedule generated from uploaded prescriptions
    state = AsyncValue.data([
      ScheduledDose(
        id: 'd1',
        medicationName: 'Lisinopril',
        strength: '10 mg',
        instructions: 'Take 1 tablet by mouth daily',
        scheduledTime: DateTime(now.year, now.month, now.day, 8, 0),
        isTaken: true,
      ),
      ScheduledDose(
        id: 'd2',
        medicationName: 'Metformin',
        strength: '500 mg',
        instructions: 'Take 1 tablet by mouth twice a day with meals',
        scheduledTime: DateTime(now.year, now.month, now.day, 8, 30),
        isTaken: true,
      ),
      ScheduledDose(
        id: 'd3',
        medicationName: 'Atorvastatin',
        strength: '20 mg',
        instructions: 'Take 1 tablet by mouth at bedtime',
        scheduledTime: DateTime(now.year, now.month, now.day, 21, 0),
        isTaken: false,
      ),
      ScheduledDose(
        id: 'd4',
        medicationName: 'Levothyroxine',
        strength: '50 mcg',
        instructions: 'Take 1 tablet by mouth on an empty stomach 30 mins before breakfast',
        scheduledTime: DateTime(now.year, now.month, now.day + 1, 7, 0),
        isTaken: false,
      ),
    ]);
  }

  Future<void> markAsTaken(String doseId, bool taken) async {
    final currentState = state.value;
    if (currentState == null) return;
    
    // Optimistic update
    final updatedList = currentState.map((d) {
      if (d.id == doseId) return d.copyWith(isTaken: taken);
      return d;
    }).toList();
    
    state = AsyncValue.data(updatedList);
    
    // Simulate network call to persist
    try {
      await Future.delayed(const Duration(milliseconds: 400));
      // In a real implementation we would await api call here.
      // throw Exception('Failed to save to server');
    } catch (e) {
      // Revert if failed
      state = AsyncValue.data(currentState);
      rethrow;
    }
  }
}

final scheduleProvider = StateNotifierProvider<ScheduleNotifier, AsyncValue<List<ScheduledDose>>>((ref) {
  return ScheduleNotifier();
});
