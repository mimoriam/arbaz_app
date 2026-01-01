import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../screens/auth/login/login_screen.dart';
import '../screens/navbar/home/home_screen.dart';
import '../screens/questionnaire/questionnaire_screen.dart';
import 'fcm_service.dart';
import 'firestore_service.dart';
import 'role_preference_service.dart';

/// Pure router - single source of truth for navigation
/// Routes based on Firebase auth state and user roles
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

        // User logged in → Check roles and route accordingly
        if (snapshot.hasData) {
          return _RoleRouter(user: snapshot.data!);
        }

        // Not logged in
        return const LoginScreen();
      },
    );
  }
}

/// Routes user based on their role state
class _RoleRouter extends StatefulWidget {
  final User user;

  const _RoleRouter({required this.user});

  @override
  State<_RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<_RoleRouter> {
  bool _isLoading = true;
  String? _error;
  String? _targetRole;

  @override
  void initState() {
    super.initState();
    _loadRoleAndRoute();
  }

  @override
  void didUpdateWidget(covariant _RoleRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the user changed (e.g., different account), re-fetch roles
    if (oldWidget.user.uid != widget.user.uid) {
      setState(() {
        _isLoading = true;
        _error = null;
        _targetRole = null;
      });
      _loadRoleAndRoute();
    }
  }

  Future<void> _loadRoleAndRoute() async {
    try {
      final firestoreService = context.read<FirestoreService>();
      final rolePreferenceService = context.read<RolePreferenceService>();
      final uid = widget.user.uid;

      // 1. Check Firestore for user roles
      final roles = await firestoreService.getUserRoles(uid);

      // 2. If no roles assigned, show questionnaire
      if (roles == null || roles.currentRole == 'unassigned') {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _targetRole = null; // null means show questionnaire
          });
        }
        return;
      }

      // 3. Check local preference for active role
      String? activeRole = await rolePreferenceService.getActiveRole(uid);
      
      debugPrint('🔐 AuthGate: uid=$uid');
      debugPrint('🔐 AuthGate: localPref=$activeRole');
      debugPrint('🔐 AuthGate: firestoreActiveRole=${roles.activeRole}');
      debugPrint('🔐 AuthGate: isSenior=${roles.isSenior}, isFamilyMember=${roles.isFamilyMember}');

      // 4. If no local preference, use Firestore role and save it
      if (activeRole == null) {
        // First try Firestore's persisted activeRole
        if (roles.activeRole != null && 
            (roles.activeRole == 'senior' || roles.activeRole == 'family')) {
          activeRole = roles.activeRole;
        }
        // Fall back to role flags - prefer family if only family, senior if only senior
        else if (roles.isFamilyMember && !roles.isSenior) {
          activeRole = 'family';
        } else if (roles.isSenior && !roles.isFamilyMember) {
          activeRole = 'senior';
        } else if (roles.isSenior && roles.isFamilyMember) {
          // User has both roles - default to senior (legacy behavior or if no preference sent)
          activeRole = 'senior';
        } else {
          // Edge case: roles exist but neither flag is true
          if (mounted) {
            setState(() {
              _isLoading = false;
              _targetRole = null;
            });
          }
          return;
        }
        
        // Save to local preference for future runs
        if (activeRole != null) {
          await rolePreferenceService.setActiveRole(uid, activeRole);
        }
      }
      
      // Register FCM token for push notifications (non-blocking, errors don't affect login)
      try {
        await FcmService().registerToken(uid);
      } catch (fcmError) {
        debugPrint('FCM registration failed (non-fatal): $fcmError');
      }
      
      debugPrint('🔐 AuthGate: FINAL activeRole=$activeRole');

      if (mounted) {
        setState(() {
          _isLoading = false;
          _targetRole = activeRole;
        });
      }
    } catch (e) {
      debugPrint('RoleRouter error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _SplashScreen();
    }

    if (_error != null) {
      return _AuthErrorScreen(error: _error!);
    }

    // No role assigned - show questionnaire
    if (_targetRole == null) {
      return const QuestionnaireScreen();
    }

    // Route to appropriate home screen
    if (_targetRole == 'senior') {
      return const SeniorHomeScreen();
    } else {
      return const FamilyHomeScreen();
    }
  }
}

/// Simple splash screen shown during auth/role resolution
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
