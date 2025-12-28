import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'services/auth_gate.dart';
import 'services/auth_service.dart';
import 'services/auth_state.dart';
import 'services/firestore_service.dart';
import 'services/qr_invite_service.dart';
import 'services/role_preference_service.dart';
import 'services/theme_provider.dart';
import 'services/vacation_mode_provider.dart';
import 'services/quotes_service.dart';
import 'services/location_service.dart';
import 'services/contacts_service.dart';
import 'services/checkin_schedule_service.dart';
import 'providers/brain_games_provider.dart';
import 'providers/checkin_schedule_provider.dart';
import 'providers/health_quiz_provider.dart';
import 'providers/escalation_alarm_provider.dart';
import 'providers/games_provider.dart';
import 'utils/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppInitializer());
}

/// Root widget that handles Firebase initialization with proper state management
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
  }

  Future<void> _initializeFirebase() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Firebase initialization failed: $e');
      debugPrint('Stack trace: $stackTrace');
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
    // Loading state
    if (_isLoading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SafeCheckTheme.lightTheme,
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    // Error state
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SafeCheckTheme.lightTheme,
        home: FirebaseErrorScreen(
          error: _error!,
          onRetry: _initializeFirebase,
        ),
      );
    }

    // Success - show main app with providers
    return MultiProvider(
      providers: [
        // Auth
        Provider(create: (_) => AuthService()),
        ChangeNotifierProxyProvider<AuthService, AuthState>(
          create: (ctx) => AuthState(ctx.read<AuthService>()),
          update: (ctx, authService, authState) =>
              authState ?? AuthState(authService),
        ),

        // Data services
        Provider(create: (_) => FirestoreService()),
        Provider(create: (_) => QrInviteService()),
        Provider(create: (_) => RolePreferenceService()),
        
        // New Services
        Provider(create: (_) => DailyQuotesService()),
        Provider(create: (_) => LocationService()),
        Provider(create: (_) => FamilyContactsService()),
        
        // Dependent Services
        ProxyProvider<FirestoreService, CheckInScheduleService>(
          update: (_, firestoreService, previous) {
            // Return existing instance if available, or create new one
            return previous ?? CheckInScheduleService(firestoreService);
          },
        ),

        // Features Providers
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => VacationModeProvider()),
        
        ChangeNotifierProxyProvider<FirestoreService, BrainGamesProvider>(
          create: (context) {
            final p = BrainGamesProvider(context.read<FirestoreService>());
            p.init();
            return p;
          },
          update: (_, firestoreService, previous) {
            if (previous != null) {
              previous.firestoreService = firestoreService;
              return previous;
            }
            final p = BrainGamesProvider(firestoreService);
            p.init();
            return p;
          },
        ),
        
        ChangeNotifierProxyProvider<CheckInScheduleService, CheckInScheduleProvider>(
          create: (context) {
            final p = CheckInScheduleProvider(context.read<CheckInScheduleService>());
            p.init();
            return p;
          },
          update: (_, scheduleService, previous) {
            if (previous != null) {
              previous.scheduleService = scheduleService;
              return previous;
            }
            final p = CheckInScheduleProvider(scheduleService);
            p.init();
            return p;
          },
        ),
        
        ChangeNotifierProxyProvider<FirestoreService, HealthQuizProvider>(
          create: (context) {
            final p = HealthQuizProvider(context.read<FirestoreService>());
            p.init();
            return p;
          },
          update: (_, firestoreService, previous) {
            if (previous != null) {
              previous.firestoreService = firestoreService;
              return previous;
            }
            final p = HealthQuizProvider(firestoreService);
            p.init();
            return p;
          },
        ),
        
        ChangeNotifierProxyProvider<FirestoreService, EscalationAlarmProvider>(
          create: (context) {
            final p = EscalationAlarmProvider(context.read<FirestoreService>());
            p.init();
            return p;
          },
          update: (_, firestoreService, previous) {
            if (previous != null) {
              previous.firestoreService = firestoreService;
              return previous;
            }
            final p = EscalationAlarmProvider(firestoreService);
            p.init();
            return p;
          },
        ),
        
        ChangeNotifierProxyProvider<FirestoreService, GamesProvider>(
          create: (context) {
            final p = GamesProvider(context.read<FirestoreService>());
            p.init();
            return p;
          },
          update: (_, firestoreService, previous) {
            if (previous != null) {
              previous.firestoreService = firestoreService;
              return previous;
            }
            final p = GamesProvider(firestoreService);
            p.init();
            return p;
          },
        ),
      ],
      child: const MainApp(),
    );
  }
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: SafeCheckTheme.lightTheme,
          darkTheme: SafeCheckTheme.darkTheme,
          themeMode: ThemeMode.light,
          // themeMode: themeProvider.themeMode,
          home: const AuthGate(), // Single source of truth for routing
        );
      },
    );
  }
}

/// Error screen shown when Firebase initialization fails
class FirebaseErrorScreen extends StatefulWidget {
  final String error;
  final Future<void> Function() onRetry;

  const FirebaseErrorScreen({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  State<FirebaseErrorScreen> createState() => _FirebaseErrorScreenState();
}

class _FirebaseErrorScreenState extends State<FirebaseErrorScreen> {
  bool _isRetrying = false;

  Future<void> _handleRetry() async {
    setState(() => _isRetrying = true);
    try {
      await widget.onRetry();
    } catch (e) {
      debugPrint('Retry failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_off,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 24),
                Text(
                  'Firebase Initialization Failed',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Unable to connect to Firebase services. Please check your internet connection and try again.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _isRetrying ? null : _handleRetry,
                  icon: _isRetrying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_isRetrying ? 'Retrying...' : 'Retry'),
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
                        widget.error,
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
      ),
    );
  }
}
