import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: HealthWalletApp()));
}

class HealthWalletApp extends ConsumerStatefulWidget {
  const HealthWalletApp({super.key});

  @override
  ConsumerState<HealthWalletApp> createState() => _HealthWalletAppState();
}

class _HealthWalletAppState extends ConsumerState<HealthWalletApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createRouter(ref);
    // When a refresh attempt fails the session has truly ended: reset auth
    // state and route back through the splash gate to a signed-out UI.
    ref.read(apiClientProvider).onSessionExpired = () {
      ref.invalidate(authProvider);
      ref.read(sessionExpiredProvider.notifier).bump();
      _router.go('/splash');
    };
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    return MaterialApp.router(
      title: 'MedSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}