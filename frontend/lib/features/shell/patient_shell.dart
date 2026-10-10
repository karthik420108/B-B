import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PatientShell extends StatelessWidget {
  const PatientShell({super.key, required this.child});

  final Widget child;

  static const _tabs = ['/home', '/reminders', '/documents', '/assistant', '/health'];

  @override
  Widget build(BuildContext context) {
    final location = GoRouter.of(context).state.uri.path;
    final index = _tabs.indexWhere((t) => location.startsWith(t));
    final current = index < 0 ? 0 : index;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: current,
        onDestinationSelected: (i) {
          final tab = _tabs[i];
          if (GoRouter.of(context).state.uri.path != tab) context.go(tab);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.alarm_outlined), selectedIcon: Icon(Icons.alarm), label: 'Reminders'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Records'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Ask AI'),
          NavigationDestination(icon: Icon(Icons.health_and_safety_outlined), selectedIcon: Icon(Icons.health_and_safety), label: 'Health'),
        ],
      ),
    );
  }
}