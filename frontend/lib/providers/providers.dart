import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../core/storage/token_storage.dart';
import '../models/models.dart';
import '../services/ai_repository.dart';
import '../services/auth_repository.dart';
import '../services/doctor_repository.dart';
import '../services/documents_repository.dart';
import '../services/patient_repository.dart';
import '../services/records_repository.dart';
import '../services/settings_repository.dart';
import '../services/share_repository.dart';

// ---------------------------------------------------------------------------
// Dependencies
// ---------------------------------------------------------------------------

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(tokenStorageProvider)));

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) => SettingsRepository());

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider), ref.watch(tokenStorageProvider)),
);

final patientRepositoryProvider = Provider<PatientRepository>(
  (ref) => PatientRepository(ref.watch(apiClientProvider)),
);

final documentsRepositoryProvider = Provider<DocumentsRepository>(
  (ref) => DocumentsRepository(ref.watch(apiClientProvider)),
);

final recordsRepositoryProvider = Provider<RecordsRepository>(
  (ref) => RecordsRepository(ref.watch(apiClientProvider)),
);

final aiRepositoryProvider = Provider<AiRepository>(
  (ref) => AiRepository(ref.watch(apiClientProvider)),
);

final shareRepositoryProvider = Provider<ShareRepository>(
  (ref) => ShareRepository(ref.watch(apiClientProvider)),
);

final doctorRepositoryProvider = Provider<DoctorRepository>(
  (ref) => DoctorRepository(ref.watch(apiClientProvider)),
);

// ---------------------------------------------------------------------------
// Auth state
// ---------------------------------------------------------------------------

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({required this.status, this.user, this.busy = false, this.error});

  final AuthStatus status;
  final User? user;
  final bool busy;
  final String? error;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isDoctor => user?.isDoctor == true;
  bool get isPatient => user?.isPatient == true;
  bool get isDoctorVerified => user?.isDoctorVerified == true;
  bool get isDoctorPendingVerification => isDoctor && !isDoctorVerified;
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unknown);

  Future<void> bootstrap() async {
    final repo = ref.read(authRepositoryProvider);
    final stored = await repo.restoreSession();
    state = stored == null
        ? const AuthState(status: AuthStatus.unauthenticated)
        : AuthState(status: AuthStatus.authenticated, user: stored);
  }

  Future<void> login({required String email, required String password}) async {
    state = state.copyWith(busy: true, error: null);
    try {
      final repo = ref.read(authRepositoryProvider);
      final data = await repo.login(email: email, password: password);
      await repo.persistSession(data);
      state = AuthState(status: AuthStatus.authenticated, user: data.user);
    } catch (e) {
      state = state.copyWith(busy: false, error: e.toString());
      rethrow;
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
    String? phone,
    String role = 'patient',
    Map<String, dynamic>? doctorProfile,
    Map<String, dynamic>? patientProfile,
  }) async {
    state = state.copyWith(busy: true, error: null);
    try {
      final repo = ref.read(authRepositoryProvider);
      final data = await repo.register(
        email: email,
        password: password,
        name: name,
        phone: phone,
        role: role,
        doctorProfile: doctorProfile,
        patientProfile: patientProfile,
      );
      await repo.persistSession(data);
      state = AuthState(status: AuthStatus.authenticated, user: data.user);
    } catch (e) {
      state = state.copyWith(busy: false, error: e.toString());
      rethrow;
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  Future<void> logout() async {
    final repo = ref.read(authRepositoryProvider);
    await repo.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

extension on AuthState {
  AuthState copyWith({AuthStatus? status, User? user, bool? busy, String? error}) => AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        busy: busy ?? this.busy,
        error: error ?? this.error,
      );
}

// ---------------------------------------------------------------------------
// Theme (persisted)
// ---------------------------------------------------------------------------

class ThemeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  Future<void> init() async {
    final repo = ref.read(settingsRepositoryProvider);
    state = await repo.loadThemeMode();
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await ref.read(settingsRepositoryProvider).saveThemeMode(mode);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(ThemeNotifier.new);

// ---------------------------------------------------------------------------
// Onboarding flag (cached in memory after startup)
// ---------------------------------------------------------------------------

class OnboardingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> init() async {
    state = await ref.read(settingsRepositoryProvider).isOnboardingDone();
  }

  Future<void> complete() async {
    await ref.read(settingsRepositoryProvider).setOnboardingDone();
    state = true;
  }
}

final onboardingProvider = NotifierProvider<OnboardingNotifier, bool>(OnboardingNotifier.new);

// ---------------------------------------------------------------------------
// Data providers (refreshed with ref.refresh/invalidate after mutations)
// ---------------------------------------------------------------------------

final dashboardProvider = FutureProvider<DashboardData>((ref) {
  return ref.watch(patientRepositoryProvider).getDashboard();
});

final timelineProvider = FutureProvider<List<TimelineItem>>((ref) {
  return ref.watch(recordsRepositoryProvider).timeline();
});

final documentsProvider = FutureProvider.autoDispose<List<DocumentSummary>>((ref) async {
  final result = await ref.watch(documentsRepositoryProvider).list();
  return result.items;
});

final observationsProvider = FutureProvider<List<Observation>>((ref) {
  return ref.watch(recordsRepositoryProvider).observations();
});

final medicationsProvider = FutureProvider<List<Medication>>((ref) {
  return ref.watch(recordsRepositoryProvider).medications();
});

final medicationSafetyProvider = FutureProvider<MedicationSafetyReport>((ref) {
  return ref.watch(recordsRepositoryProvider).medicationSafety();
});

final duplicateTestsProvider = FutureProvider.family<({List<DuplicateFinding> findings, int total}), int>((ref, windowDays) {
  return ref.watch(recordsRepositoryProvider).duplicateTests(windowDays: windowDays);
});

final sharesProvider = FutureProvider<List<ShareGrant>>((ref) {
  return ref.watch(shareRepositoryProvider).list();
});

final appointmentsProvider = FutureProvider<List<Appointment>>((ref) {
  return ref.watch(patientRepositoryProvider).getAppointments();
});

final profileProvider = FutureProvider<PatientProfile>((ref) {
  return ref.watch(patientRepositoryProvider).getProfile();
});

final doctorSharesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(doctorRepositoryProvider).myShares();
});

final aiProviderInfo = FutureProvider<Map<String, dynamic>>((ref) {
  return ref.watch(aiRepositoryProvider).providerInfo();
});

/// Monotonic latch bumped when a server-side session ends (refresh unusable),
/// so screens/widgets listening on it can react (e.g. surfaced by the router).
class SessionExpiredNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final sessionExpiredProvider = NotifierProvider<SessionExpiredNotifier, int>(SessionExpiredNotifier.new);