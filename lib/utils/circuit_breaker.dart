/// Circuit Breaker pattern implementation for resilient external service calls.
/// 
/// The circuit breaker prevents cascading failures by stopping calls to a failing
/// service after a threshold is reached, allowing the service time to recover.
/// 
/// States:
/// - CLOSED: Normal operation, calls pass through
/// - OPEN: Service is failing, calls are rejected immediately
/// - HALF_OPEN: Testing if service has recovered
/// 
/// Usage:
/// ```dart
/// final breaker = CircuitBreaker(
///   failureThreshold: 5,
///   resetTimeout: Duration(minutes: 1),
/// );
/// 
/// try {
///   final result = await breaker.call(() => someExternalService());
/// } on CircuitOpenException {
///   // Handle circuit open - use fallback or show error
/// }
/// ```
library;

import 'package:flutter/foundation.dart';

/// Exception thrown when the circuit is open and calls are being rejected.
class CircuitOpenException implements Exception {
  final String message;
  final DateTime openUntil;
  
  CircuitOpenException({
    required this.message,
    required this.openUntil,
  });
  
  @override
  String toString() => 'CircuitOpenException: $message (open until $openUntil)';
}

/// States of the circuit breaker
enum CircuitState {
  closed,   // Normal operation
  open,     // Rejecting calls
  halfOpen, // Testing recovery
}

/// A circuit breaker for protecting external service calls.
/// 
/// Tracks failures and opens the circuit after [failureThreshold] consecutive
/// failures. The circuit stays open for [resetTimeout] before allowing a
/// test call through.
class CircuitBreaker {
  /// Number of consecutive failures before opening the circuit
  final int failureThreshold;
  
  /// Duration the circuit stays open before attempting recovery
  final Duration resetTimeout;
  
  /// Optional name for logging purposes
  final String? name;
  
  int _consecutiveFailures = 0;
  DateTime? _openUntil;
  CircuitState _state = CircuitState.closed;
  
  CircuitBreaker({
    this.failureThreshold = 5,
    this.resetTimeout = const Duration(minutes: 1),
    this.name,
  });
  
  /// Current state of the circuit
  CircuitState get state => _state;
  
  /// Whether the circuit is currently allowing calls
  bool get isAllowingCalls => _state != CircuitState.open;
  
  /// Number of consecutive failures
  int get consecutiveFailures => _consecutiveFailures;
  
  /// Execute an operation through the circuit breaker.
  /// 
  /// Throws [CircuitOpenException] if the circuit is open.
  /// On success, resets the failure count.
  /// On failure, increments failure count and may open the circuit.
  Future<T> call<T>(Future<T> Function() operation) async {
    // Check if circuit should transition from open to half-open
    _checkStateTransition();
    
    // Reject call if circuit is open
    if (_state == CircuitState.open) {
      final serviceName = name ?? 'external service';
      throw CircuitOpenException(
        message: 'Circuit breaker for $serviceName is open',
        openUntil: _openUntil!,
      );
    }
    
    try {
      final result = await operation();
      _onSuccess();
      return result;
    } catch (e) {
      _onFailure(e);
      rethrow;
    }
  }
  
  /// Call that returns null instead of throwing when circuit is open.
  /// Useful for non-critical operations where fallback to null is acceptable.
  Future<T?> callOrNull<T>(Future<T> Function() operation) async {
    try {
      return await call(operation);
    } on CircuitOpenException {
      return null;
    }
  }
  
  /// Manually reset the circuit breaker to closed state.
  void reset() {
    _consecutiveFailures = 0;
    _openUntil = null;
    _state = CircuitState.closed;
    _log('Circuit manually reset to CLOSED');
  }
  
  /// Check and handle state transitions
  void _checkStateTransition() {
    if (_state == CircuitState.open && _openUntil != null) {
      if (DateTime.now().isAfter(_openUntil!)) {
        // Transition to half-open to test if service has recovered
        _state = CircuitState.halfOpen;
        _log('Circuit transitioned to HALF_OPEN');
      }
    }
  }
  
  /// Handle successful operation
  void _onSuccess() {
    if (_state == CircuitState.halfOpen) {
      // Service has recovered, close the circuit
      _log('Circuit CLOSED after successful test call');
    }
    _consecutiveFailures = 0;
    _openUntil = null;
    _state = CircuitState.closed;
  }
  
  /// Handle failed operation
  void _onFailure(Object error) {
    _consecutiveFailures++;
    
    if (_state == CircuitState.halfOpen) {
      // Failed during recovery test, reopen circuit
      _openCircuit();
      _log('Circuit reopened after failed test call: $error');
    } else if (_consecutiveFailures >= failureThreshold) {
      // Threshold reached, open circuit
      _openCircuit();
      _log('Circuit OPENED after $failureThreshold consecutive failures: $error');
    }
  }
  
  /// Open the circuit
  void _openCircuit() {
    _state = CircuitState.open;
    _openUntil = DateTime.now().add(resetTimeout);
  }
  
  void _log(String message) {
    final prefix = name != null ? '[$name] ' : '';
    debugPrint('CircuitBreaker: $prefix$message');
  }
}

/// A collection of circuit breakers for different services.
/// 
/// Provides named access to circuit breakers with consistent configuration.
class CircuitBreakerRegistry {
  static final CircuitBreakerRegistry _instance = CircuitBreakerRegistry._internal();
  factory CircuitBreakerRegistry() => _instance;
  CircuitBreakerRegistry._internal();
  
  final Map<String, CircuitBreaker> _breakers = {};
  
  /// Get or create a circuit breaker for the given service name.
  /// 
  /// **Note**: If a breaker with [name] already exists, it is returned as-is
  /// and the provided [failureThreshold] and [resetTimeout] are ignored.
  /// A warning is logged if the parameters differ from the existing breaker.
  CircuitBreaker getBreaker(
    String name, {
    int failureThreshold = 5,
    Duration resetTimeout = const Duration(minutes: 1),
  }) {
    final existing = _breakers[name];
    if (existing != null) {
      // Warn if requested config differs from existing breaker
      if (existing.failureThreshold != failureThreshold ||
          existing.resetTimeout != resetTimeout) {
        debugPrint(
          'CircuitBreakerRegistry: Returning existing breaker for "$name" '
          'with different configuration than requested '
          '(existing: threshold=${existing.failureThreshold}, timeout=${existing.resetTimeout}; '
          'requested: threshold=$failureThreshold, timeout=$resetTimeout)',
        );
      }
      return existing;
    }
    
    // Create new breaker with provided configuration
    final breaker = CircuitBreaker(
      name: name,
      failureThreshold: failureThreshold,
      resetTimeout: resetTimeout,
    );
    _breakers[name] = breaker;
    return breaker;
  }
  
  /// Pre-configured breaker for Firestore operations
  CircuitBreaker get firestore => getBreaker(
    'firestore',
    failureThreshold: 5,
    resetTimeout: const Duration(minutes: 1),
  );
  
  /// Pre-configured breaker for FCM operations
  CircuitBreaker get fcm => getBreaker(
    'fcm',
    failureThreshold: 3,
    resetTimeout: const Duration(minutes: 2),
  );
  
  /// Pre-configured breaker for Cloud Tasks operations
  CircuitBreaker get cloudTasks => getBreaker(
    'cloudTasks',
    failureThreshold: 3,
    resetTimeout: const Duration(minutes: 2),
  );
  
  /// Reset all circuit breakers
  void resetAll() {
    for (final breaker in _breakers.values) {
      breaker.reset();
    }
  }
}
