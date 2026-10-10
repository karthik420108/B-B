import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/shell/patient_shell.dart';
import '../../features/home/home_screen.dart';
import '../../features/reminders/reminders_screen.dart';
import '../../features/reminders/add_medication_screen.dart';
import '../../features/reminders/schedule_detail_screen.dart';
import '../../features/reminders/history_screen.dart';
import '../../features/reminders/prescription_extract_screen.dart';
import '../../features/documents/documents_screen.dart';
import '../../features/documents/document_detail_screen.dart';
import '../../features/documents/upload_screen.dart';
import '../../features/documents/review_screen.dart';
import '../../features/ai/assistant_screen.dart';
import '../../features/health/health_hub_screen.dart';
import '../../features/medications/medications_screen.dart';
import '../../features/medications/safety_screen.dart';
import '../../features/duplicates/duplicates_screen.dart';
import '../../features/summary/summary_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/medical_profile_screen.dart';
import '../../features/emergency/emergency_card_screen.dart';
import '../../features/sharing/shares_screen.dart';
import '../../features/sharing/create_share_screen.dart';
import '../../features/sharing/share_detail_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/doctor/doctor_home_screen.dart';
import '../../features/doctor/doctor_bundle_screen.dart';
import '../../features/doctor/pending_verification_screen.dart';

const _publicPaths = {'/login', '/register', '/forgot-password', '/onboarding'};

/// App router with role-based guards:
///  - while bootstrapping only `/splash` is reachable,
///  - unauthenticated users only reach the public paths,
///  - doctors are confined to `/doctor*`, patients to the rest.
GoRouter createRouter(WidgetRef ref) {
  return GoRouter(
    initialLocation: '/splash',
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final path = state.uri.path;
      final authed = auth.isAuthenticated;

      if (auth.status == AuthStatus.unknown && path != '/splash') {
        return '/splash';
      }

      if (path == '/splash') {
        if (authed) return auth.isDoctor ? '/doctor' : '/home';
        return null; // splash decides next step by showing login/onboarding
      }

      if (!authed) {
        if (_publicPaths.contains(path)) return null;
        return '/login';
      }

      if (auth.isDoctor) {
        // Unverified doctors can only see the pending-verification screen.
        if (auth.isDoctorPendingVerification) {
          return path == '/doctor/pending' ? null : '/doctor/pending';
        }
        if (path == '/doctor/pending') return '/doctor';
        if (path == '/doctor' || path.startsWith('/doctor/')) return null;
        return '/doctor';
      }

      // Authenticated patient.
      if (path.startsWith('/doctor')) return '/home';
      if (_publicPaths.contains(path)) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (c, s) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/register', builder: (c, s) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (c, s) => const ForgotPasswordScreen()),
      ShellRoute(
        builder: (context, state, child) => PatientShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (c, s) => const HomeScreen()),
          GoRoute(path: '/reminders', builder: (c, s) => const RemindersScreen()),
          GoRoute(path: '/documents', builder: (c, s) => const DocumentsScreen()),
          GoRoute(path: '/assistant', builder: (c, s) => const AssistantScreen()),
          GoRoute(path: '/health', builder: (c, s) => const HealthHubScreen()),
        ],
      ),
      GoRoute(path: '/reminders/add', builder: (c, s) => const AddMedicationScreen()),
      GoRoute(path: '/reminders/history', builder: (c, s) => const MedicationHistoryScreen()),
      GoRoute(path: '/reminders/extract', builder: (c, s) => PrescriptionExtractScreen(documentId: s.uri.queryParameters['documentId'])),
      GoRoute(path: '/reminders/schedule/:id', builder: (c, s) => ScheduleDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/documents/upload', builder: (c, s) => const UploadScreen()),
      GoRoute(path: '/documents/:id', builder: (c, s) => DocumentDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/documents/:id/review', builder: (c, s) => ReviewScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/medications', builder: (c, s) => const MedicationsScreen()),
      GoRoute(path: '/medications/safety', builder: (c, s) => const SafetyScreen()),
      GoRoute(path: '/duplicates', builder: (c, s) => const DuplicatesScreen()),
      GoRoute(path: '/summary', builder: (c, s) => const SummaryScreen()),
      GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
      GoRoute(path: '/profile/medical', builder: (c, s) => const MedicalProfileScreen()),
      GoRoute(path: '/emergency', builder: (c, s) => const EmergencyCardScreen()),
      GoRoute(path: '/share', builder: (c, s) => const SharesScreen()),
      GoRoute(path: '/share/create', builder: (c, s) => const CreateShareScreen()),
      GoRoute(path: '/share/:id', builder: (c, s) => ShareDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
      GoRoute(path: '/notifications', builder: (c, s) => const NotificationsScreen()),
      GoRoute(path: '/doctor', builder: (c, s) => const DoctorHomeScreen()),
      GoRoute(path: '/doctor/pending', builder: (c, s) => const PendingVerificationScreen()),
      GoRoute(path: '/doctor/:token', builder: (c, s) => DoctorBundleScreen(token: s.pathParameters['token']!)),
    ],
  );
}