import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_init_provider.dart';

/// Full-screen loading screen displayed during app initialisation.
///
/// Reads [AppInitProvider] to show an animated progress bar and a
/// human-readable description of the current startup stage so the user
/// knows exactly what is happening and the app never shows a blank screen.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Consumer<AppInitProvider>(
        builder: (context, init, _) {
          return SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── App icon ──────────────────────────────────────────
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.psychology_rounded,
                        size: 56,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── App name ──────────────────────────────────────────
                    Text(
                      'Smriti',
                      style: textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Offline Knowledge Assistant',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 56),

                    // ── Progress bar ──────────────────────────────────────
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        // null → indeterminate (animated) until progress > 0
                        value: init.progress > 0.0 ? init.progress : null,
                        minHeight: 6,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          init.hasError
                              ? colorScheme.error
                              : colorScheme.primary,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Stage message (animated cross-fade) ───────────────
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      child: Text(
                        init.hasError
                            ? (init.errorMessage ??
                                'An error occurred during startup.')
                            : init.message,
                        key: ValueKey(init.message + (init.hasError ? '!' : '')),
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall?.copyWith(
                          color: init.hasError
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),

                    // ── Error hint ────────────────────────────────────────
                    if (init.hasError) ...[
                      const SizedBox(height: 28),
                      Icon(
                        Icons.warning_amber_rounded,
                        color: colorScheme.error,
                        size: 32,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Some services failed to start. '
                        'The app may still work in limited mode.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
