import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/utils/formatters.dart';

/// Standard async-state wrapper: loading / error / ready.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.onReady,
    this.loading,
    this.onRetry,
    this.padding,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) onReady;
  final Widget? loading;
  final VoidCallback? onRetry;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: onReady,
      loading: () => loading ?? const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorPanel(error: err, onRetry: onRetry, padding: padding),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, this.onRetry, this.padding});

  final Object error;
  final VoidCallback? onRetry;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = error is ApiException
        ? (error as ApiException).message
        : error is NetworkException
            ? (error as NetworkException).message
            : error.toString();
    return Center(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('Something went wrong', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              // Scale the retry button down when the panel is given very little
              // room (narrow panes, small dialogs) instead of overflowing.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, this.icon = Icons.inbox_outlined, required this.title, this.subtitle, this.action});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.icon, required this.title, this.subtitle, this.trailing, required this.child});

  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      if (subtitle != null)
                        Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
                if (trailing != null) ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// A tappable list-style card for hub screens.
class HubTile extends StatelessWidget {
  const HubTile({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.badge, this.badgeColor});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final int? badge;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: Icon(icon),
        ),
        title: Text(title, style: theme.textTheme.titleSmall),
        subtitle: subtitle == null ? null : Text(subtitle!, style: theme.textTheme.bodySmall),
        trailing: badge == null
            ? const Icon(Icons.chevron_right)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Badge(
                    backgroundColor: badgeColor ?? theme.colorScheme.error,
                    label: Text('$badge'),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              ),
        onTap: onTap,
      ),
    );
  }
}

/// Verification chip showing source and state of an extracted resource.
class VerificationChip extends StatelessWidget {
  const VerificationChip({super.key, required this.verification, this.source});

  final String? verification;
  final String? source;

  @override
  Widget build(BuildContext context) {
    final color = verificationColor(context, verification);
    return Chip(
      avatar: Icon(Icons.verified_outlined, size: 16, color: color),
      label: Text(verificationLabel(verification)),
      labelStyle: TextStyle(color: color, fontSize: 12),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.4)),
    );
  }
}

/// Small "recorded at PROVIDER • DATE" caption used across screens.
class MetaLine extends StatelessWidget {
  const MetaLine({super.key, this.provider, this.date, this.extra});

  final String? provider;
  final String? date;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (provider != null && provider!.isNotEmpty) provider!,
      if (date != null && date!.isNotEmpty) date!,
      if (extra != null && extra!.isNotEmpty) extra!,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join('  •  '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
    );
  }
}

/// Refreshable scaffold body helper.
class RefreshScaffold extends StatelessWidget {
  const RefreshScaffold({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(onRefresh: onRefresh, child: child);
  }
}