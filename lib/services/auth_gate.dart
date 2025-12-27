import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/auth/login/login_screen.dart';
import '../screens/questionnaire/questionnaire_screen.dart';

/// Pure router - single source of truth for navigation
/// Routes based on Firebase auth state only
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Still resolving auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }

        // Error state
        if (snapshot.hasError) {
          debugPrint('AuthGate: Auth stream error - ${snapshot.error}');
          return _AuthErrorScreen(
            error: snapshot.error.toString(),
          );
        }
        // User logged in → Role selection on every login
        if (snapshot.hasData) {
          return const QuestionnaireScreen();
        }

        // Not logged in
        return const LoginScreen();
      },
    );
  }
}

/// Simple splash screen shown during auth resolution
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

/// Error screen shown if auth stream errors
class _AuthErrorScreen extends StatelessWidget {
  final String error;

  const _AuthErrorScreen({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Authentication Error',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'There was a problem with authentication. Please try again.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  // Re-initialize auth flow by replacing with new AuthGate
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const AuthGate(),
                    ),
                  );
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                title: const Text('Error Details'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SelectableText(
                      error,
                      style: GoogleFonts.robotoMono(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
